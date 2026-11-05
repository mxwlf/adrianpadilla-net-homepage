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

# OpenTofu, for the test environment in infra/test/. Not installed by
# `make setup` — it is a separate toolchain, like `gh`.
TOFU ?= tofu
INFRA_TEST := infra/test

.PHONY: help setup venv check-python hooks \
        dev build clean clean-venv fmt lint test a11y lighthouse ci \
        reports sbom package \
        check-tofu tf-fmt tf-fmt-check tf-validate tf-bootstrap tf-init tf-plan tf-apply \
        rulesets-apply rulesets-diff rulesets-export \
        environments-apply environments-diff environments-show

help: ## Show available targets
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

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

build: ## Build the site into dist/, generate the sitemap, validate the HTML
	npm run build
	node scripts/generate-sitemap.mjs
	npm run lint:html

fmt: ## Auto-format supported files
	npm run fmt

lint: ## Run the site's linters, no auto-fix (Prettier, ESLint, Stylelint)
	npm run lint

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

ci: hooks lint tf-fmt-check build test ## Full gate: git hygiene + lint + infra format + build + test

hooks: venv ## Run all pre-commit hooks against all files (same hooks as the git hooks)
	$(PRE_COMMIT) run --all-files --show-diff-on-failure

# ---------------------------------------------------------------------------
# INFRASTRUCTURE (OpenTofu, test environment)
# ---------------------------------------------------------------------------
# infra/test/ describes test.adrianpadilla.net. See infra/test/main.tf for what
# it deliberately does NOT manage (DNS, and the resource group).
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
		echo '       The site gate needs it to check infra/test/ formatting:' 1>&2; \
		echo '           brew install opentofu' 1>&2; \
		echo '       See https://opentofu.org/docs/intro/install/ for other systems.' 1>&2; \
		exit 1; \
	}

tf-fmt: check-tofu ## Rewrite infra/ into canonical OpenTofu formatting
	$(TOFU) -chdir=$(INFRA_TEST) fmt

tf-fmt-check: check-tofu ## Fail if infra/ is not canonically formatted
	$(TOFU) -chdir=$(INFRA_TEST) fmt -check -diff

tf-validate: check-tofu ## Download providers and validate infra/ (no credentials needed)
	$(TOFU) -chdir=$(INFRA_TEST) init -backend=false -input=false
	$(TOFU) -chdir=$(INFRA_TEST) validate

tf-bootstrap: ## Create the Blob Storage that holds the test environment's state (run once)
	./scripts/tf-bootstrap.sh

tf-init: check-tofu ## Initialise the backend from infra/test/backend.config
	@test -f $(INFRA_TEST)/backend.config || { \
		echo 'Error: $(INFRA_TEST)/backend.config does not exist.' 1>&2; \
		echo '       Create the state storage first:' 1>&2; \
		echo '           SUBSCRIPTION_ID=<guid> RESOURCE_GROUP=<name> make tf-bootstrap' 1>&2; \
		exit 1; \
	}
	$(TOFU) -chdir=$(INFRA_TEST) init -input=false -backend-config=backend.config

tf-plan: tf-init ## Show what would change in the test environment
	$(TOFU) -chdir=$(INFRA_TEST) plan

tf-apply: tf-init ## Apply the test environment
	$(TOFU) -chdir=$(INFRA_TEST) apply

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
