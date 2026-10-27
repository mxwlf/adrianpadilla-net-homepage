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

scripts/                     # Post-build: sitemap generator, headers copy; ruleset management
tests/
├── unit/                    # Node built-in test runner
├── e2e/                     # Playwright: navigation, no-JS fallback
└── a11y/                    # Playwright + axe-core: zero a11y violations
ops/headers/                 # HTTP security headers per hosting provider
.github/workflows/           # CI/CD pipelines (see below)
.github/rulesets/            # Branch protection as code (see below)
.githooks/                   # Committed git hooks, activated by `make setup`
.claude/                     # Claude Code governance (rules, agents, skills, hooks)
```

## Getting Started

```bash
make setup        # One time: commit hooks + .venv (see below)
npm install
npm run dev       # Dev server with live reload
```

Visit `http://localhost:8080`.

`make setup` is a **one-time** step per clone (or per worktree). It is required
before `make ci` will run, and it activates the commit hooks — see
[Commit hygiene](#commit-hygiene).

## Commands

| Command                | Purpose                                                       |
| ---------------------- | ------------------------------------------------------------- |
| `make setup`           | One-time: create `.venv` and activate the committed git hooks |
| `make dev`             | Dev server with live reload                                   |
| `make build`           | Build site + generate sitemap + validate HTML                 |
| `make lint`            | Run the site's linters (Prettier, ESLint, Stylelint)          |
| `make hooks`           | Run the pre-commit hooks against all files                    |
| `make test`            | Run unit + e2e tests                                          |
| `make a11y`            | axe-core accessibility audit                                  |
| `make lighthouse`      | Lighthouse CI budget check                                    |
| `make ci`              | Full gate: hooks + lint + build + test (same as CI)           |
| `make clean`           | Remove `dist/`, caches, and test artifacts                    |
| `make clean-venv`      | Remove `.venv` (rebuild with `make setup`)                    |
| `make rulesets-apply`  | Create/update this repo's branch protection on GitHub         |
| `make rulesets-diff`   | Report drift between `.github/rulesets/` and GitHub           |
| `make rulesets-export` | Pull GitHub's live branch protection back into the repo       |

Run `make` (or `make help`) for the same list, generated from the Makefile.

## Commit hygiene

Two toolchains meet in this repo. **Node** (`package.json`) builds, lints and
tests the site. **Python** (`requirements-dev.txt`) provides nothing but a pinned
[`pre-commit`](https://pre-commit.com), which runs the git hooks. Neither is
installed globally: `npm ci` manages `node_modules/`, and `make setup` creates a
repo-local `.venv/`.

`make setup` runs `git config --local include.path ../.gitconfig`, which makes
the repo include the committed [`.gitconfig`](.gitconfig). That sets
`core.hooksPath = .githooks/`, activating the committed hooks — so
`pre-commit install` is never needed, and the hooks run `.venv`'s `pre-commit`
by absolute path rather than whatever is on your `PATH`.

| Hook                                           | Enforces                                                                                                                                                                                  |
| ---------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`.githooks/pre-commit`](.githooks/pre-commit) | Trailing whitespace, end-of-file, YAML syntax, large files, case conflicts, merge markers, private keys, line endings, and a [gitleaks](https://github.com/gitleaks/gitleaks) secret scan |
| [`.githooks/commit-msg`](.githooks/commit-msg) | [Conventional Commits](https://www.conventionalcommits.org/) message format, via commitizen                                                                                               |

So commit messages must look like:

```
feat: add dark mode toggle
fix(a11y): restore focus outline on nav links
chore: bump dependencies
```

`make ci` runs the same hooks via `make hooks`, so CI catches anything that
reached a branch without them (a commit made before `make setup`, or with
`--no-verify`).

These hooks deliberately cover **git hygiene only**. The site's own formatting
and linting stays in `make lint` / `npm run lint`, so the editor, the CLI and CI
all share one config.

> **Why a `.venv` instead of a global Python?** The commitizen and
> sync-pre-commit-deps hooks are `language: python` and need Python >= 3.10, but
> their manifests say `language_version: python3` — which pre-commit resolves to
> _the interpreter running pre-commit itself_, not to whatever `python3` is on
> your `PATH`. A pre-commit installed under macOS's bundled Python 3.9 therefore
> builds those hooks with 3.9 and fails with `requires a different Python`.
> Running pre-commit from `.venv/` (built from any Python >= 3.10) sidesteps that
> without pinning interpreter versions per hook or touching your system Python.
> Point make at a specific interpreter with `make setup PYTHON=python3.12`.

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

| Workflow         | Trigger            | Purpose                                         | Blocks merge |
| ---------------- | ------------------ | ----------------------------------------------- | ------------ |
| `ci.yml`         | PR, push to `main` | `make ci` — hooks + lint + build + test         | yes (`ci`)   |
| `lighthouse.yml` | PR, push to `main` | Lighthouse budgets (perf ≥0.90, a11y/SEO ≥0.95) | yes          |
| `security.yml`   | PR, push, weekly   | CodeQL SAST, OSV-Scanner, dependency review     | partly¹      |
| `secrets.yml`    | PR, push, weekly   | Gitleaks secret scanning                        | yes          |
| `linkcheck.yml`  | PR, weekly         | Broken link detection                           | no²          |
| `deploy.yml`     | Push to `main`     | Deploy to GitHub Pages                          | n/a          |
| `monitor.yml`    | Weekly             | Production Lighthouse + security header checks  | n/a          |

¹ `dependency-review` and `osv-scan` block; `codeql` does not, because its own
`if:` excludes pull requests. ² Lychee resolves external URLs, so it fails on
other people's outages. Both exclusions are explained in
[`.github/rulesets/README.md`](.github/rulesets/README.md).

`ci.yml` is a **thin wrapper**: it checks out the code, installs Node and
Python, and runs `make ci`. All the check logic lives in the `Makefile`,
`package.json` and `.pre-commit-config.yaml`, so the gate a pull request faces
is byte-for-byte the one you can run locally. To change _what_ CI does, edit
those files — not the workflow YAML.

## Branch protection

CI that merely _reports_ a failure does not keep a broken commit off `main`: a
commit cannot be rejected for failing CI, because CI only starts once the commit
exists. What protects the branch is a rule that refuses the merge until the
checks have passed, and that lives on GitHub's side rather than in a git hook.

Those rules are kept **in the repo**, as
[`.github/rulesets/*.json`](.github/rulesets/), and rebuilt with the GitHub CLI:

```sh
make rulesets-apply     # create/update the rulesets on GitHub
make rulesets-diff      # fail if GitHub no longer matches the repo
make rulesets-export    # overwrite the JSON from GitHub (after a UI edit)
```

These need `gh`, authenticated with admin rights on the repo. Unlike everything
else, `gh` is **not** installed by `make setup`, and these targets are
deliberately **not** part of `make ci` — a workflow's default `GITHUB_TOKEN`
cannot read rulesets, so wiring them into CI would fail for reasons unrelated to
the code under test. See
[`.github/rulesets/README.md`](.github/rulesets/README.md) for what the rules
enforce and why each required check was chosen.

### The workflow these rules require

The workflow is **trunk-based**. `main` is the only long-lived branch; everything
else is a short-lived branch that exists just long enough to carry one pull
request, and is deleted after it merges.

1. **Branch off `main`.** Name it however you like — the rules place no
   constraint on source branches. Commits are checked locally by the hooks from
   `make setup`.
2. **Open a pull request into `main`.** A direct `git push origin main` is
   rejected by the ruleset, as is a force-push and a branch deletion.
3. **Let the required checks pass.** The merge button stays disabled until `ci`,
   `lighthouse`, `dependency-review`, `osv-scan` and `gitleaks` all report
   success. The branch must also be up to date with `main` first, so if `main`
   moved, update the branch and let them run again.
4. **Merge with a merge commit, then delete the branch.** `main` accepts _only_
   merge commits — squash and rebase are not offered. That choice is about
   authorship: a merge commit leaves your commits untouched, so each keeps the
   signature you made, and GitHub signs the merge commit itself to satisfy the
   signed-commits rule. The trade is that `main` is not linear.

What this buys, and what it does not: the rules keep a red build from reaching
`main` by accident. They are not a hard stop, because a repository admin can
bypass them _inside_ a pull request — which is also what makes the required
approval satisfiable on a one-maintainer repo, since you cannot approve your own
pull request.

> **Keep the check names and the triggers in sync.** Each required check is a
> **job id** in `.github/workflows/`, and that workflow's `pull_request` trigger
> must cover every branch the rulesets protect. Rename a job, or protect a new
> branch without extending the trigger, and the required check is simply never
> reported — the pull request then waits on it indefinitely rather than failing.

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

The one non-Node dependency is [`pre-commit`](requirements-dev.txt), pinned and
installed into `.venv/` by `make setup`. It never reaches the browser either —
it only runs the git hooks.

## Troubleshooting

- **`` `pre-commit` was not found in this repository's .venv/ ``** — the venv is
  missing (fresh clone, new worktree, or `make clean-venv`). Run `make setup`
  from the repository root.
- **`Error: python3 ... but >= 3.10 is required`** — the interpreter make would
  use to build `.venv` is too old. Install any newer Python and either put it on
  your `PATH` as `python3` or pass it explicitly:
  `make setup PYTHON=python3.12`. You do **not** need to change your system
  default.
- **commitizen / sync-pre-commit-deps fails to build / `requires a different Python`** —
  the hooks are being run by a pre-commit _outside_ `.venv/`. Confirm
  `make setup` has been run and that `git config --get core.hooksPath` prints
  `.githooks/`; if a stray `pre-commit install` overwrote `.git/hooks/`, delete
  those generated files so `core.hooksPath` takes effect again.
- **`.venv` broke after a Python upgrade** (e.g. Homebrew replaced the
  interpreter it was built from) — recreate it: `make clean-venv && make setup`.
- **Hook is ignored / not running** — confirm `make setup` has been run
  (`git config --get include.path` should print `../.gitconfig`) and that the
  hook scripts in `.githooks/` are executable.
- **A pull request waits forever on a required check** — the check is never being
  reported. Confirm the job id in `.github/workflows/` still matches the
  `context` in `.github/rulesets/main-protection.json`, and that the workflow's
  `pull_request` trigger covers the target branch.
- **`make rulesets-diff` reports drift after a GitHub UI edit** — run
  `make rulesets-export` to bring the change into the repo, or
  `make rulesets-apply` to discard it and restore the committed rules.

## Credits

The git hygiene, `make ci` thin-wrapper and branch-protection-as-code layers
come from [mxwlf/git-template](https://github.com/mxwlf/git-template).
