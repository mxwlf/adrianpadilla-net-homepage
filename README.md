# webpage-static-template

A production-quality static website template. Fast, accessible, SEO-friendly, and deployable to any static host.

**Philosophy**: HTML-first, CSS-first, minimal JS.

## Stack

- **[Eleventy](https://www.11ty.dev/) v3** — static site generator (`src/` → `dist/`)
- **[Nunjucks](https://mozilla.github.io/nunjucks/)** — templating language
- No CSS framework, no JS framework — hand-authored HTML and CSS only

## Project Structure

```
src/
├── _data/site.json          # Global site metadata (URL, title, author, etc.)
├── _includes/
│   ├── layouts/base.njk     # Base HTML layout (SEO, OG tags, skip link)
│   └── partials/            # Header and footer partials
├── pages/                   # Homepage, About, 404
└── assets/
    ├── css/main.css         # Hand-authored CSS (reset, typography, a11y, layout)
    ├── js/main.js           # Minimal JS placeholder
    └── vendor/              # Self-hosted third-party scripts (currently empty)

scripts/                     # Post-build: sitemap generator, headers copy
tests/
├── unit/                    # Node built-in test runner
├── e2e/                     # Playwright: navigation, no-JS fallback
└── a11y/                    # Playwright + axe-core: zero a11y violations
ops/headers/                 # HTTP security headers per hosting provider
.github/workflows/           # CI/CD pipeline (see below)
.claude/                     # Claude Code governance (rules, agents, skills, hooks)
```

## Getting Started

```bash
npm install
npm run dev       # Dev server with live reload
```

Visit `http://localhost:8080`.

## Commands

| Command           | Purpose                                                      |
| ----------------- | ------------------------------------------------------------ |
| `make dev`        | Dev server with live reload                                  |
| `make build`      | Build site + generate sitemap                                |
| `make lint`       | Run all linters (Prettier, ESLint, Stylelint, html-validate) |
| `make test`       | Run unit + e2e tests                                         |
| `make a11y`       | axe-core accessibility audit                                 |
| `make lighthouse` | Lighthouse CI budget check                                   |
| `make ci`         | Full gate: lint + test + build (same as CI)                  |
| `make clean`      | Remove `dist/`, caches, and test artifacts                   |

## Configuration

Edit `src/_data/site.json` to set your site's URL, title, description, and author. This file is the single source of truth for global metadata used across all pages and SEO tags.

## Security Headers

Provider-specific HTTP security headers (CSP, X-Frame-Options, Referrer-Policy, etc.) live in `ops/headers/` and are copied into `dist/` at build time via `HOSTING_TARGET`:

```bash
HOSTING_TARGET=netlify make build
HOSTING_TARGET=cloudflare make build
```

See `docs/hosting-setup.md` for full setup instructions.

## CI/CD

All workflows run via GitHub Actions:

| Workflow         | Trigger            | Purpose                                         |
| ---------------- | ------------------ | ----------------------------------------------- |
| `ci.yml`         | PR, push to `main` | Lint + test + build                             |
| `deploy.yml`     | Push to `main`     | Deploy to GitHub Pages                          |
| `lighthouse.yml` | PR, push to `main` | Lighthouse budgets (perf ≥0.90, a11y/SEO ≥0.95) |
| `security.yml`   | PR, push, weekly   | CodeQL SAST, OSV-Scanner, dependency review     |
| `secrets.yml`    | PR, push, weekly   | Gitleaks secret scanning                        |
| `linkcheck.yml`  | PR, weekly         | Broken link detection                           |
| `monitor.yml`    | Weekly             | Production Lighthouse + security header checks  |

## Accessibility

Accessibility is first-class:

- Skip-to-content link, `aria-current="page"` on nav, semantic landmark roles
- `lang` attribute, `:focus-visible` styles, `prefers-reduced-motion` support
- axe-core test suite asserts zero violations on every page
- Lighthouse a11y budget enforced at ≥0.95

## Dependencies

All packages are `devDependencies` — there are no npm packages shipped to the browser.

| Package                | Role                     |
| ---------------------- | ------------------------ |
| `@11ty/eleventy`       | Static site generator    |
| `@axe-core/playwright` | Accessibility scanning   |
| `@lhci/cli`            | Lighthouse CI runner     |
| `@playwright/test`     | E2E and a11y tests       |
| `eslint`               | JavaScript linting       |
| `html-validate`        | HTML/Nunjucks validation |
| `prettier`             | Code formatting          |
| `stylelint`            | CSS linting              |
