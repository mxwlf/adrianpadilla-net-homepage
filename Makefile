SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: help
help:
	@echo "Targets:"
	@echo "  make dev             Run local dev server"
	@echo "  make build           Build site into dist/"
	@echo "  make clean           Remove dist/"
	@echo "  make fmt             Auto-format supported files"
	@echo "  make lint            Run linters (no auto-fix)"
	@echo "  make test            Run unit + e2e tests"
	@echo "  make a11y            Run a11y checks"
	@echo "  make lighthouse       Run Lighthouse CI locally (lab)"
	@echo "  make ci              CI bundle (lint + test + build)"

.PHONY: dev
dev:
	npm run dev

.PHONY: clean
clean:
	rm -rf dist .cache .lighthouseci playwright-report test-results

.PHONY: build
build:
	npm run build
	node scripts/generate-sitemap.mjs
	npm run lint:html

.PHONY: fmt
fmt:
	npm run fmt

.PHONY: lint
lint:
	npm run lint

.PHONY: test
test:
	npm run test:unit
	npm run test:e2e

.PHONY: a11y
a11y:
	npm run test:a11y

.PHONY: lighthouse
lighthouse:
	npm run lighthouse

.PHONY: ci
ci: lint build test
