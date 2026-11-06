# Project constitution — adrianpadilla.net

## Non-negotiables

- Site must work without JavaScript (progressive enhancement is mandatory).
- Any new interactive behavior must have an accessible baseline (keyboard + screen readers).
- Keep JS minimal; prefer HTML/CSS first.
- No regressions allowed in: Lighthouse budgets, a11y tests, HTML validation, and security scans.

## Local contract

- Run `make setup` once per clone or worktree. It creates `.venv/` and activates
  the committed git hooks; `make ci` fails without it.
- `make ci` also needs **OpenTofu** (`brew install opentofu`), which `make setup`
  does not install — it checks `infra/` formatting alongside everything else.
- Always run: `make ci` before opening a PR.
- If CI fails, fix the root cause (do not disable gates without explicit approval).
- Commit messages must follow Conventional Commits; the `commit-msg` hook enforces it.
- Work lands on **`develop`** by pull request. `main` is the record of what is in
  production. Both are protected; never push to either directly, and never use
  `--no-verify`.

## Architecture

- Eleventy builds from `src/` to `dist/`.
- `scripts/generate-sitemap.mjs` writes `dist/sitemap.xml`.
- `make ci` is the single gate; the workflows in `.github/workflows/` are thin
  wrappers around it. Change what CI does in the `Makefile`, `package.json` or
  `.pre-commit-config.yaml`, not in workflow YAML.
- **The pipeline builds once and promotes the result.** A merge to `develop`
  produces one versioned, hash-verified release package; the test environment
  deploys it automatically and production deploys the _same bytes_ after you
  approve. Nothing rebuilds on the way to production. See
  @docs/deployment.md.
- **Host configuration is infrastructure, content is the artifact.**
  `staticwebapp.config.json` is never copied into the build output; per-
  environment variants are written at packaging time and selected at deploy.
  See @docs/hosting-setup.md.
- **Three things are code, not settings**, and each has a `make` target plus a
  README explaining what the API cannot reproduce:
  - branch protection — `.github/rulesets/*.json`, `make rulesets-apply`
  - deployment environments — `.github/environments/*.json`, `make environments-apply`
  - action dependencies — `.github/workflows/actions.lock`, `make actions-lock`
- A required check's `context` is a workflow job id — renaming one without the
  other makes PRs hang forever. A job with a `paths:` filter must never be
  required, for the same reason.
- `infra/test/` and `infra/prod/` describe both environments in OpenTofu, in the
  same shape. Every `tf-*` target takes `INFRA_ENV`, defaulting to `test`:
  `make tf-plan INFRA_ENV=prod`. Neither owns any DNS — the
  `adrianpadilla.net` zone also serves several unrelated services, so no
  OpenTofu configuration here is allowed zone-level DNS rights and every
  production record is made by hand. Production's apex binding is likewise
  manual, because only `cname-delegation` validation is polled by the provider.
  The cutover runbook is in @docs/deployment.md.
- **The test environment is disposable, and that is the one DNS exception.**
  `make test-env-teardown` destroys the test Static Web App — never its resource
  group, which `infra/test/` reads with a `data` block and so cannot destroy —
  and parks `test.adrianpadilla.net` on production. `make test-env-restore`
  rebuilds it and repoints the record; `release.yml` runs that before every
  deploy to test, so **deploying is what switches the DNS back**. A rebuilt app
  gets a new `*.azurestaticapps.net` hostname, so that record cannot be static;
  leaving it on a released hostname would be a dangling-CNAME takeover. The test
  identity therefore holds `DNS Zone Contributor` scoped to the single
  `CNAME/test` record set and nothing wider, and `scripts/test-env.sh` only ever
  writes that record, never deletes it. The production identity still holds no
  DNS permission at all.
- Parking is not redirecting. `test.adrianpadilla.net` resolves into production
  but is bound to nothing there — production is Free SKU with both custom-domain
  slots spent — so it does not answer 301. Do not "fix" that by binding it to
  the production app: `staticwebapp.config.json` cannot match on `Host`, so
  production would serve its own content and canonicals on the test hostname
  without `X-Robots-Tag: noindex`. See @docs/deployment.md.

## References

- See @.claude/rules/performance.md
- See @.claude/rules/a11y.md
- See @.claude/rules/security.md
- See @.claude/rules/seo.md
- See @.claude/rules/ci-contract.md
