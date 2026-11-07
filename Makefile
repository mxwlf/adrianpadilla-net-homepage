# Makefile for adrianpadilla.net
#
# `make ci` is the SINGLE command CI/CD pipelines invoke, and it runs
# identically on a developer laptop. All check logic lives here, in-repo; the
# platform YAML in .github/workflows/ is a thin wrapper around it.
#
# Two toolchains meet in this file:
#   - Node (package.json)        — the site itself: build, lint, test, Lighthouse.
#   - Python (.venv/)            — git hygiene: the pre-commit hooks.
#
# Neither is installed globally. `npm ci` manages node_modules/, and
# `make setup` creates .venv/ from requirements-dev.txt.
#
# Usage:
#   make            # same as `make help`
#   make setup      # create .venv + configure the repo's git config and hooks
#   make ci         # run the full gate (what pipelines invoke)
#
#   make rulesets-apply    # rebuild this repo's GitHub branch protection
#   make rulesets-diff     # check live branch protection against the repo
#   make rulesets-export   # save live branch protection into the repo
#
#   make test-env-status   # is the test environment up, and where does its DNS point
#   make test-env-teardown # destroy the test Static Web App, park its DNS
#   make test-env-restore  # rebuild it and point its DNS back
#
# Requirements:
#   - GNU make, git, and a POSIX shell (on Windows: Git Bash or WSL).
#   - Node 20+ and npm, for everything that touches the site.
#   - A Python interpreter >= $(MIN_PYTHON) reachable as `python3`. It is used
#     ONLY to create the virtualenv, so it can be any install you already have
#     (system, Homebrew, pyenv, ...). Point make at a specific one with:
#         make setup PYTHON=/path/to/python3.12
#
# How `make setup` works:
#     1. Builds .venv/ and installs the pinned tooling into it.
#     2. Runs `git config --local include.path ../.gitconfig`, which makes this
#        repo's local config include the committed `.gitconfig`. That in turn
#        sets `core.hooksPath = .githooks/`, activating the committed hook
#        scripts (pre-commit and commit-msg) without needing `pre-commit
#        install`. Those scripts run .venv's `pre-commit`, never PATH's.

SHELL := /bin/bash
.DEFAULT_GOAL := help

# ---------------------------------------------------------------------------
# REPO-LOCAL VIRTUALENV
# ---------------------------------------------------------------------------
# The interpreter used only to *create* .venv. Override on the command line
# (e.g. `make setup PYTHON=python3.12`) to build the venv from a specific one.
PYTHON ?= python3

# Minimum version for the interpreter above: some hooks (commitizen,
# sync-pre-commit-deps) are `language: python` and require >= 3.10. Because
# their manifests say `language_version: python3`, pre-commit builds them with
# whichever interpreter is running pre-commit itself — i.e. .venv's.
MIN_PYTHON := 3.10

VENV := .venv
ifeq ($(OS),Windows_NT)
VENV_BIN := $(VENV)/Scripts
else
VENV_BIN := $(VENV)/bin
endif
PRE_COMMIT := $(VENV_BIN)/pre-commit
# Marker file recording that requirements-dev.txt has been installed into
# .venv; makes `venv` a no-op until the requirements change.
VENV_STAMP := $(VENV)/.requirements-installed

RULESETS := ./scripts/github-rulesets.sh
ENVIRONMENTS := ./scripts/github-environments.sh

# OpenTofu, for the environments in infra/*/. Not installed by
# `make setup` — it is a separate toolchain, like `gh`.
TOFU ?= tofu
# Which environment the tf-* targets act on. There are two, and they are the
# same shape, so the directory is a variable rather than a second set of
# targets:
#     make tf-plan                 # test, the default
#     make tf-plan INFRA_ENV=prod  # production
INFRA_ENV ?= test
INFRA_DIR := infra/$(INFRA_ENV)
# Every environment, for the checks that should cover all of them regardless of
# which one you are working on.
INFRA_DIRS := $(wildcard infra/*/)

.PHONY: help setup venv check-python hooks \
        dev build clean clean-venv fmt lint lint-html test a11y lighthouse ci \
        reports sbom package \
        check-tofu tf-fmt tf-fmt-check tf-validate tf-bootstrap tf-init tf-plan tf-apply \
        test-env-status test-env-teardown test-env-restore \
        check-gh-actions-lock actions-lock actions-lock-verify actions-lock-verify-local \
        rulesets-apply rulesets-diff rulesets-export \
        environments-apply environments-diff environments-show

help: ## Show available targets
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-26s\033[0m %s\n", $$1, $$2}'

# ---------------------------------------------------------------------------
# SETUP
# ---------------------------------------------------------------------------

setup: venv ## Create .venv and configure the repo's git config + commit hooks
	git config --local include.path ../.gitconfig
	$(PRE_COMMIT) install-hooks

venv: $(VENV_STAMP) ## Create/update the repo-local virtualenv (.venv) with the pinned tooling

$(VENV_STAMP): requirements-dev.txt
	@$(MAKE) --no-print-directory check-python
	$(PYTHON) -m venv $(VENV)
	$(VENV_BIN)/python -m pip install --disable-pip-version-check --upgrade pip
	$(VENV_BIN)/python -m pip install --disable-pip-version-check --require-virtualenv -r requirements-dev.txt
	@touch $@

check-python: ## Verify the interpreter used to build .venv is new enough
	@command -v $(PYTHON) > /dev/null 2>&1 || { \
		echo 'Error: `$(PYTHON)` was not found on your PATH.' 1>&2; \
		echo '       Install any Python >= $(MIN_PYTHON), or point make at one you have:' 1>&2; \
		echo '           make setup PYTHON=/path/to/python3' 1>&2; \
		exit 1; \
	}
	@$(PYTHON) -c 'import sys; req = tuple(int(p) for p in "$(MIN_PYTHON)".split(".")); raise SystemExit(sys.version_info[:len(req)] < req)' || { \
		echo "Error: $(PYTHON) is $$($(PYTHON) -V 2>&1 | cut -d" " -f2), but >= $(MIN_PYTHON) is required to build $(VENV)." 1>&2; \
		echo '       Any interpreter >= $(MIN_PYTHON) will do; it need not be your default python3:' 1>&2; \
		echo '           make setup PYTHON=python3.12' 1>&2; \
		exit 1; \
	}

# ---------------------------------------------------------------------------
# SITE
# ---------------------------------------------------------------------------

dev: ## Run local dev server with live reload
	npm run dev

build: ## Build the site into dist/ and generate the sitemap
	# dist/ is emptied first. Eleventy writes into its output directory without
	# purging it, and assets are content-hash fingerprinted, so editing a file
	# leaves the previous `main.<oldhash>.css` behind forever. Nothing referenced
	# it, so nothing failed -- it simply accumulated, and `make package` folded
	# the orphans into site/ and into the digest that is supposed to identify the
	# release. A laptop that had built the site twice produced a different
	# siteSha256 from CI, which gets a fresh checkout every run.
	#
	# This is the root cause, so it is fixed here rather than in `package`: every
	# consumer of `build` gets a dist/ that contains only what this commit emits.
	#
	# This target does NOT validate the HTML it produces. It used to, which made
	# html-validate run once per build -- and `make package` builds, then runs
	# `report:html` over the same dist/, so the same tool graded the same bytes
	# twice in the same job, seconds apart. Validation is `lint-html` now: once
	# in `ci`, once in report form in `reports`. See docs/pipeline-map.md.
	rm -rf dist
	npm run build
	node scripts/generate-sitemap.mjs

fmt: ## Auto-format supported files
	npm run fmt

lint: ## Run the site's linters, no auto-fix (Prettier, ESLint, Stylelint)
	npm run lint

lint-html: ## Validate the built HTML (run `make build` first)
	npm run lint:html

test: ## Run unit + e2e tests
	npm run test:unit
	npm run test:e2e

a11y: ## Run the axe-core accessibility audit
	npm run test:a11y

lighthouse: ## Run Lighthouse CI locally (lab budgets)
	npm run lighthouse

# ---------------------------------------------------------------------------
# RELEASE PACKAGING
# ---------------------------------------------------------------------------
# The pipeline builds ONCE and promotes the result. These targets turn a build
# into the versioned package that the test environment and production both
# deploy from, so a promotion never rebuilds. See scripts/release-package.mjs.
#
# `package` needs a version, because the package is named by one:
#     make package RELEASE_VERSION=1.2.3
# The release workflow passes the version release-please resolved. Locally,
# anything will do — the package is then throwaway.

RELEASE_VERSION ?=
RELEASE_COMMIT ?= $(shell git rev-parse HEAD)

reports: build ## Re-run every gate in report-producing mode into reports/
	# Emptied first: lhci writes a timestamped filename per run and never
	# overwrites, so without this a second `make package` ships both runs'
	# Lighthouse reports and the package's evidence becomes an accumulation
	# rather than a description of this build.
	rm -rf reports
	@mkdir -p reports/html-validate reports/playwright reports/a11y reports/lighthouse
	npm run --silent report:html > reports/html-validate/report.json
	PLAYWRIGHT_JSON_OUTPUT_NAME=$(CURDIR)/reports/playwright/report.json npm run --silent report:e2e
	PLAYWRIGHT_JSON_OUTPUT_NAME=$(CURDIR)/reports/a11y/report.json npm run --silent report:a11y
	npm run --silent report:lighthouse

sbom: ## Write a CycloneDX SBOM of the dependency tree to sbom/
	@mkdir -p sbom
	npm run --silent sbom

package: reports sbom ## Assemble the versioned, hash-verified release package in release/
	@test -n "$(RELEASE_VERSION)" || { \
		echo 'Error: RELEASE_VERSION is required.' 1>&2; \
		echo '       make package RELEASE_VERSION=1.2.3' 1>&2; \
		exit 1; \
	}
	RELEASE_VERSION=$(RELEASE_VERSION) RELEASE_COMMIT=$(RELEASE_COMMIT) \
		node scripts/release-package.mjs
	cd release && sha256sum -c SHA256SUMS > /dev/null && echo "SHA256SUMS verified"

clean: ## Remove dist/, caches, and test and release artifacts
	rm -rf dist .cache .lighthouseci playwright-report test-results reports sbom release

clean-venv: ## Remove .venv (rebuild it with `make setup`)
	rm -rf $(VENV)

# ---------------------------------------------------------------------------
# CI ENTRYPOINT
# ---------------------------------------------------------------------------
# The single command .github/workflows/ci.yml invokes. `hooks` runs the same
# git-hygiene checks the commit hooks run, so CI catches them on any commit
# that reached the branch without them (e.g. made before `make setup`, or with
# --no-verify).
#
# `a11y` is in this list, and was not. axe ran only inside `make package`, which
# happens after the tag exists -- so an accessibility regression merged freely
# and first failed while packaging a release. The project's non-negotiables say
# a11y must not regress, which means it has to be a gate and not a report. It
# needs a browser, like `test` does, and ci.yml already installs one.
#
# The order is load-bearing: `build` populates dist/, and `lint-html`, `test`
# and `a11y` all read it.

ci: hooks lint tf-fmt-check build lint-html test a11y ## Full gate: git hygiene + lint + infra format + build + HTML + tests + a11y

hooks: venv ## Run all pre-commit hooks against all files (same hooks as the git hooks)
	$(PRE_COMMIT) run --all-files --show-diff-on-failure

# ---------------------------------------------------------------------------
# INFRASTRUCTURE (OpenTofu)
# ---------------------------------------------------------------------------
# infra/test/ describes test.adrianpadilla.net and infra/prod/ describes
# adrianpadilla.net, in the same shape. See each main.tf for what it
# deliberately does NOT manage (DNS, the resource group, and for prod the apex
# domain binding).
#
# Only `tf-fmt-check` is part of `ci`. It parses the HCL, so a malformed file
# still cannot merge, and it needs no providers and no network. `tf-validate`
# does need providers: `tofu init` downloads the azurerm plugin, which is a few
# hundred megabytes, and making every `make ci` on every laptop pay that would
# break the rule that the gate is cheap enough to run before every push. It runs
# instead as its own job, with the plugin directory cached — see
# .github/workflows/infra.yml.
#
# tf-plan and tf-apply need Azure credentials and are never part of any gate.

check-tofu: ## Verify OpenTofu is installed
	@command -v $(TOFU) > /dev/null 2>&1 || { \
		echo 'Error: `$(TOFU)` was not found on your PATH.' 1>&2; \
		echo '       The site gate needs it to check infra/ formatting:' 1>&2; \
		echo '           brew install opentofu' 1>&2; \
		echo '       See https://opentofu.org/docs/intro/install/ for other systems.' 1>&2; \
		exit 1; \
	}

tf-fmt: check-tofu ## Rewrite every infra/ environment into canonical formatting
	$(TOFU) fmt -recursive infra

# -recursive so adding an environment cannot quietly escape the gate, which a
# per-directory invocation would have allowed. (Kept outside the recipe: a
# tab-indented comment is handed to the shell, which echoes it.)
tf-fmt-check: check-tofu ## Fail if any infra/ environment is not canonically formatted
	$(TOFU) fmt -recursive -check -diff infra

tf-validate: check-tofu ## Download providers and validate every infra/ environment (no credentials)
	@for d in $(INFRA_DIRS); do \
		echo "==> $$d"; \
		$(TOFU) -chdir=$$d init -backend=false -input=false || exit 1; \
		$(TOFU) -chdir=$$d validate || exit 1; \
	done

tf-bootstrap: ## Create the Blob Storage holding an environment's state (run once per environment)
	INFRA_ENV=$(INFRA_ENV) ./scripts/tf-bootstrap.sh

tf-init: check-tofu ## Initialise the backend from infra/$(INFRA_ENV)/backend.config
	@test -f $(INFRA_DIR)/backend.config || { \
		echo 'Error: $(INFRA_DIR)/backend.config does not exist.' 1>&2; \
		echo '       Create the state storage first:' 1>&2; \
		echo '           SUBSCRIPTION_ID=<guid> RESOURCE_GROUP=<name> make tf-bootstrap INFRA_ENV=$(INFRA_ENV)' 1>&2; \
		exit 1; \
	}
	$(TOFU) -chdir=$(INFRA_DIR) init -input=false -backend-config=backend.config

# TF_ARGS exists for the one operation that cannot be expressed as "apply the
# whole configuration": a domain cutover. A hostname can be bound to only one
# Static Web App at a time, so standing up a replacement means applying the app
# first, moving DNS, and only then applying the binding —
#   make tf-apply INFRA_ENV=prod TF_ARGS='-target=azurerm_static_web_app.prod'
# It is deliberately empty by default and used by no automation.
TF_ARGS ?=

tf-plan: tf-init ## Show what would change (INFRA_ENV=test|prod)
	$(TOFU) -chdir=$(INFRA_DIR) plan $(TF_ARGS)

tf-apply: tf-init ## Apply an environment (INFRA_ENV=test|prod)
	$(TOFU) -chdir=$(INFRA_DIR) apply $(TF_ARGS)

# ---------------------------------------------------------------------------
# TEST ENVIRONMENT LIFECYCLE
# ---------------------------------------------------------------------------
# Teardown and restore for the test environment, including the one DNS record.
# See scripts/test-env.sh for why DNS is now automated — at record-set scope —
# when every other record in that zone is still made by hand.
#
# These take NO INFRA_ENV, deliberately, and the script refuses to look at any
# directory but infra/test/. Every other tf-* target is parameterised by
# environment; a `make test-env-teardown INFRA_ENV=prod` that worked would be a
# one-command outage, so the parameter does not exist here.
#
# The resource group is never destroyed: infra/test/ reads it with a `data`
# block, so it is not in the state file, and `test-env-teardown` asserts that
# before it destroys anything.
#
# `test-env-restore` is idempotent and is what release.yml runs before every
# deploy to test — that is the mechanism by which a deployment puts
# test.adrianpadilla.net back on the test environment.

TEST_ENV := ./scripts/test-env.sh

test-env-status: check-tofu ## Report whether the test environment is up and where its DNS points
	$(TEST_ENV) status

test-env-teardown: check-tofu ## Destroy the test Static Web App (not its group) and park its DNS at production
	$(TEST_ENV) teardown

test-env-restore: check-tofu ## Recreate the test Static Web App and point its DNS back at it (idempotent)
	$(TEST_ENV) restore

# ---------------------------------------------------------------------------
# ACTIONS DEPENDENCY LOCKFILE
# ---------------------------------------------------------------------------
# .github/workflows/actions.lock pins every action the workflows use —
# including the transitive ones that a SHA in a `uses:` line cannot reach — to a
# commit, and records the source repository's numeric owner/repo ids so a
# renamed or taken-over repository is rejected at run time.
#
# Generated by the `gh actions-lock` extension and never edited by hand:
#     gh extension install github/gh-actions-lock
#
# Deliberately NOT part of `ci`, for the same reason as the rulesets and
# environments targets: they need `gh`, which `make setup` does not install and
# which the repository treats as a separate toolchain. Verification runs as its
# own job instead, see .github/workflows/actions-lock.yml.
#
# Two verifications, and the difference matters:
#   verify        resolves every ref upstream. Catches a moved tag, a rewritten
#                 history, or a repository that is no longer the one that was
#                 locked. Needs network and a token.
#   verify-local  only checks that every `uses:` has a lockfile entry. No
#                 network, no token. Fast, but it cannot tell you whether the
#                 entries are still trustworthy.

ACTIONS_LOCK := gh actions-lock

check-gh-actions-lock: ## Verify the gh actions-lock extension is installed
	@gh extension list 2>/dev/null | grep -q gh-actions-lock || { \
		echo 'Error: the `gh actions-lock` extension is not installed.' 1>&2; \
		echo '           gh extension install github/gh-actions-lock' 1>&2; \
		exit 1; \
	}

actions-lock: check-gh-actions-lock ## Regenerate the actions lockfile from the workflows
	$(ACTIONS_LOCK) --no-interactive

actions-lock-verify: check-gh-actions-lock ## Verify the lockfile against upstream (network + token)
	$(ACTIONS_LOCK) --verify

actions-lock-verify-local: check-gh-actions-lock ## Check lockfile coverage offline (no network, no token)
	$(ACTIONS_LOCK) --verify-local

# ---------------------------------------------------------------------------
# GITHUB RULESETS (branch protection as code)
# ---------------------------------------------------------------------------
# Branch protection lives in .github/rulesets/*.json and is reconciled by name.
# See scripts/github-rulesets.sh and .github/rulesets/README.md.
#
# These targets are deliberately NOT dependencies of `ci`: rulesets are admin
# API surface, and a workflow's default GITHUB_TOKEN cannot read them. Making
# `ci` depend on them would fail for reasons unrelated to the code under test,
# and would break the rule that `make ci` runs identically on a laptop.
#
# Requires the GitHub CLI (`gh`), authenticated — unlike the targets above, this
# is not covered by `make setup`. Target another repo with REPO=owner/name.

rulesets-apply: ## Create/update this repo's GitHub rulesets from .github/rulesets/
	$(RULESETS) apply

rulesets-diff: ## Report drift between .github/rulesets/ and the live rulesets
	$(RULESETS) diff

rulesets-export: ## Overwrite .github/rulesets/ with the live rulesets
	$(RULESETS) export

# ---------------------------------------------------------------------------
# GITHUB DEPLOYMENT ENVIRONMENTS (the approval gate, as code)
# ---------------------------------------------------------------------------
# .github/environments/*.json. production carries a required reviewer, which is
# what makes a promotion pause for a human and what makes GitHub record the
# result as a Deployment. Not part of `ci` for the same reason as the rulesets
# targets: writing environments needs admin rights a GITHUB_TOKEN cannot hold.

environments-apply: ## Create/update the deployment environments from .github/environments/
	$(ENVIRONMENTS) apply

environments-diff: ## Report drift between .github/environments/ and GitHub
	$(ENVIRONMENTS) diff

environments-show: ## Print the live configuration of each committed environment
	$(ENVIRONMENTS) show
