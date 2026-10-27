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

.PHONY: help setup venv check-python hooks \
        dev build clean clean-venv fmt lint test a11y lighthouse ci \
        rulesets-apply rulesets-diff rulesets-export

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

clean: ## Remove dist/, caches, and test artifacts
	rm -rf dist .cache .lighthouseci playwright-report test-results

clean-venv: ## Remove .venv (rebuild it with `make setup`)
	rm -rf $(VENV)

# ---------------------------------------------------------------------------
# CI ENTRYPOINT
# ---------------------------------------------------------------------------
# The single command .github/workflows/ci.yml invokes. `hooks` runs the same
# git-hygiene checks the commit hooks run, so CI catches them on any commit
# that reached the branch without them (e.g. made before `make setup`, or with
# --no-verify).

ci: hooks lint build test ## Full gate: git hygiene + lint + build + test

hooks: venv ## Run all pre-commit hooks against all files (same hooks as the git hooks)
	$(PRE_COMMIT) run --all-files --show-diff-on-failure

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
