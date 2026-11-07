# Pipeline map

Every automated action in this repository, what triggers it, and which of those
actions run more than once on the same content.

[`deployment.md`](deployment.md) answers "how does a change reach production".
This file answers a narrower question that is easy to lose track of once there
are a dozen workflow files: **what actually executes, and when.** It exists
because the workflows are thin wrappers around `make`, so reading the YAML tells
you almost nothing about the work — `make ci` is one line in `ci.yml` and twelve
distinct checks in the `Makefile`.

Keep it current when you change a trigger or a `make` target. A map that is
wrong is worse than no map, because it gets trusted.

## The stages

Seven trigger points. The two that matter most are the ends: a pull request,
where everything is gated, and a manual dispatch, where production is reached.

```
 local            pull_request       push develop      release:published   dispatch       push main
──────────────────────────────────────────────────────────────────────────────────────────────────────
 pre-commit       ci            *    ci                package              promote    │  ci            *
 commit-msg       lighthouse    *    lighthouse        ├─ ensure-test       └─ record ─┼▶ lighthouse    *
 make ci (hand)   dependency-   *    codeql            └─ deploy-test                  │  codeql
                  review             osv-scan                                          │  osv-scan      *
                  osv-scan      *    gitleaks          (test env; no                   │  gitleaks      *
                  gitleaks      *    actions-lock       reviewer, so it                │  actions-lock
                  actions-lock       infra (paths)      just goes)                     │
                  infra (paths)      release-please                                    │
                  lychee                                                               │
                                                     ─── no automatic path ────────────┘
                                                         crosses into production

 workflow_dispatch, on its own:  test-env  (teardown | restore | status)

 weekly:  codeql + osv-scan (Mon 04:17)   gitleaks (Sun 03:41)   lychee (Tue 02:13)
          monitor: prod Lighthouse + header check (Mon 06:00)
          dependabot: npm, actions (7-day cooldown on actions)

 * = required status check on both develop-protection and main-protection
```

One structural fact the diagram in `deployment.md` does not show: **`record`
advancing `main` re-enters the pipeline from the top.** It pushes with a GitHub
App token, and unlike `GITHUB_TOKEN` that does start workflows — the same
mechanism `release-please.yml` depends on. So the full pull-request suite runs
once more against a tree that is already serving production traffic.

## What triggers what

| Workflow             | Trigger                                       | Jobs                                      |
| -------------------- | --------------------------------------------- | ----------------------------------------- |
| `ci.yml`             | `pull_request`, push `main`/`develop`         | `ci`                                      |
| `lighthouse.yml`     | `pull_request`, push `main`/`develop`         | `lighthouse`                              |
| `security.yml`       | `pull_request`, push `main`/`develop`, weekly | `dependency-review`, `codeql`, `osv-scan` |
| `secrets.yml`        | `pull_request`, push `main`/`develop`, weekly | `gitleaks`                                |
| `actions-lock.yml`   | `pull_request`, push `main`/`develop`         | `actions-lock`                            |
| `infra.yml`          | `pull_request` + push, `paths:` filtered      | `infra`                                   |
| `linkcheck.yml`      | `pull_request`, weekly                        | `lychee`                                  |
| `release-please.yml` | push `develop`                                | `release-please`                          |
| `release.yml`        | `release: published`                          | `package` → `ensure-test` → `deploy-test` |
| `promote-prod.yml`   | `workflow_dispatch` **only**                  | `promote` → `record`                      |
| `test-env.yml`       | `workflow_dispatch` **only**                  | `test-env`                                |
| `monitor.yml`        | weekly                                        | `lighthouse`, `security-headers`          |

Two jobs are deliberately **not** required checks, for reasons that are easy to
undo by accident:

- `infra` has a `paths:` filter. A required check that does not run on every
  pull request is never reported, and GitHub waits on it forever.
- `codeql` excludes pull requests with an `if:`, and GitHub reports a skipped
  job as successful — a required check that is always green.

`actions-lock` has neither problem. It runs unconditionally on every pull
request and is not required either; its own header comment says it was written
that way so it _could_ be required.

## Inventory

`make` and `npm` targets are expanded, because that is where the work is.

### `ci` — ci.yml, the gate

checkout · setup-node (npm cache) · setup-python 3.14 · setup-opentofu 1.13.8 ·
cache `~/.cache/pre-commit` · `npm ci` · `playwright install --with-deps chromium`
· **`make ci`** · upload `dist` artifact

`make ci` is `hooks lint tf-fmt-check build test`:

| Step           | Commands                                                                                                                                                                                                                                                                                   |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `hooks`        | `pre-commit run --all-files` — 12 hooks: sync-pre-commit-deps, trailing-whitespace, end-of-file-fixer, check-yaml, check-added-large-files, check-case-conflict, check-illegal-windows-names, check-merge-conflict, detect-private-key, fix-byte-order-marker, mixed-line-ending, gitleaks |
| `lint`         | `prettier . --check` · `eslint .` · `stylelint src/assets/css/**/*.css`                                                                                                                                                                                                                    |
| `tf-fmt-check` | `tofu fmt -recursive -check -diff infra`                                                                                                                                                                                                                                                   |
| `build`        | `rm -rf dist` · `eleventy` · `scripts/generate-sitemap.mjs` · `html-validate dist/**/*.html`                                                                                                                                                                                               |
| `test`         | `node --test` · `playwright test` (serves `dist` on :4173)                                                                                                                                                                                                                                 |

`a11y` is a `make` target but is **not** in `ci` — see [Gaps](#gaps).

### `lighthouse` — lighthouse.yml

checkout · setup-node · `npm ci` · **`make build`** (a second full build) ·
`lhci autorun` — 3 runs over `staticDistDir: dist`, asserting performance ≥ 0.9
and accessibility / best-practices / SEO ≥ 0.95, uploading to
`temporary-public-storage` · upload `.lighthouseci`

### Security and supply chain

| Job                 | Actions                                                                                                                                                                 |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `dependency-review` | dependency-review-action, `fail-on-severity: high`. Pull requests only.                                                                                                 |
| `codeql`            | init (`javascript`) · autobuild · analyze. Everything except pull requests.                                                                                             |
| `osv-scan`          | osv-scanner `--recursive --no-resolve .` — lockfiles in full, manifests unresolved.                                                                                     |
| `gitleaks`          | checkout `fetch-depth: 0` · gitleaks-action, which walks the commit range through the API.                                                                              |
| `actions-lock`      | install `gh-actions-lock` · `make actions-lock-verify` — resolves every action ref upstream, including transitive ones, and checks the source repository's numeric ids. |
| `lychee`            | link check over the tree; accepts 429; excludes the two self-referential release URLs.                                                                                  |
| `infra`             | setup-opentofu · cache `infra/*/.terraform` · `make tf-validate` = `tofu init -backend=false` + `validate`, per environment. No credentials.                            |

### `release-please` — release-please.yml

Mints a GitHub App token, then keeps a release pull request open against
`develop`. Merging it writes `CHANGELOG.md`, bumps `version.txt` and the
manifest, creates the tag and **publishes the Release** — which is what starts
`release.yml`.

### `package` — release.yml, the only place an artifact is built

checkout **the tag** · setup-node · `npm ci` · `playwright install chromium` ·
strip the leading `v` from the tag · **`make package`** · `tar -czf` ·
**attest-build-provenance** · `gh release upload` (archive, `SHA256SUMS`,
`manifest.json`)

`make package` is `reports sbom` then the assembly:

| Step                | Commands                                                                                                                                                                       |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `reports` → `build` | the same `rm -rf dist` · `eleventy` · sitemap · `html-validate` as `make ci`                                                                                                   |
| `reports`           | `rm -rf reports` · `report:html` (html-validate, JSON) · `report:e2e` (Playwright, JSON) · `report:a11y` (axe, JSON) · `report:lighthouse` (`lhci autorun`, filesystem upload) |
| `sbom`              | `cyclonedx-npm` → `sbom/bom.cdx.json`                                                                                                                                          |
| assembly            | `release-package.mjs`: `site/` (minus `staticwebapp.config.json`), `host-config/{prod,test}/`, `reports/`, `sbom/`, `SHA256SUMS` over `site/`+`sbom/`, `manifest.json`         |
| verify              | `sha256sum -c SHA256SUMS`                                                                                                                                                      |

### `ensure-test` — release.yml

checkout the tag · setup-opentofu · azure/login (test identity, OIDC) · write
`infra/test/backend.config` and `terraform.tfvars` from repository variables ·
**`make test-env-restore`** → `scripts/test-env.sh restore`:

`tofu init` · read `default_host_name` and `custom_domain` from state · if the
app is up and the CNAME already matches, one reconciling `tofu apply` and stop ·
otherwise `tofu apply -target=azurerm_static_web_app.test` · `az network dns
record-set cname set-record` pointing `test.adrianpadilla.net` at the new
`*.azurestaticapps.net` hostname · poll the authoritative record until it reads
back · `tofu apply` (binds the custom domain) · poll
`az staticwebapp hostname show` until the certificate reports `Ready`

It shares `concurrency: test-env` with `test-env.yml` so a dispatched teardown
cannot land between the two applies.

### `deploy-test` — release.yml

`needs: [package, ensure-test]`

checkout the tag · setup-node · `npm ci` (for the pinned SWA CLI) ·
`gh release download` + untar · **`gh attestation verify`** against this repo and
this workflow · `sha256sum -c SHA256SUMS` · azure/login (test identity) ·
`az staticwebapp secrets list` for the deployment token ·
`swa deploy package/site --swa-config-location package/host-config/test --env production`
· smoke test: `X-Robots-Tag: noindex` **present**, canonical still points at
production · assert no Static Web Apps staging environments exist

### `promote` and `record` — promote-prod.yml

`workflow_dispatch` with a version, pausing on the `production` environment's
required reviewer.

checkout · setup-node · `npm ci` · reject a leading `v` and anything that is not
a semantic version · `gh release download` + untar · **`gh attestation verify`** ·
`sha256sum -c SHA256SUMS`, check `manifest.version` matches the requested
version, check `siteSha256` is a 64-character hex digest before it reaches
`$GITHUB_OUTPUT` · azure/login (production identity) · fetch the deployment token
· `swa deploy package/site --swa-config-location package/host-config/prod --env production`
· smoke test: `X-Robots-Tag: noindex` **absent**, `Content-Security-Policy`
present · assert no staging environments

`record` then mints an App token and `POST /repos/{repo}/merges` with
`base=main`, `head=v$VERSION`, branching on the status code: 201 advanced, 204
already an ancestor (every rollback), 403 the App is not a bypass actor.

### `test-env` — test-env.yml

`workflow_dispatch` only, with `teardown | restore | status` and a typed
confirmation for teardown. Writes the same backend config as `ensure-test`, then
runs `make test-env-{action}`:

- **teardown** — assert no managed `azurerm_resource_group` is in the state,
  point the CNAME at `www.adrianpadilla.net` **first**, then
  `tofu destroy`. DNS moves before the destroy so the record never names a
  released Azure hostname.
- **restore** — as `ensure-test` above.
- **status** — report what the state file and the live CNAME each say.

### `monitor.yml`

- `lighthouse` — fail if `vars.PROD_URL` is unset, then `lhci autorun` 3 runs
  against the live site.
- `security-headers` — `curl -sI` and check four headers. Emits `::warning::`
  only, so **this job cannot fail**.

## What runs more than once

Because `strict_required_status_checks_policy` forces the head branch up to date
and only merge commits are allowed, four events share one **byte-identical
tree**: the release pull request, the merge of it onto `develop`, the tag, and
`main` after `record`. Counted on that tree:

| Work                           | Runs   | Can the result differ?                                                                      |
| ------------------------------ | ------ | ------------------------------------------------------------------------------------------- |
| `eleventy` build + sitemap     | **7**  | No. `make build` starts with `rm -rf dist` precisely so output is a function of the commit. |
| `html-validate` over `dist/**` | **8**  | No. Once per build, plus `report:html`.                                                     |
| Playwright e2e                 | **4**  | Only by flake (2 retries in CI).                                                            |
| `pre-commit run --all-files`   | **3**  | No.                                                                                         |
| `tofu fmt -check`              | **3**  | No.                                                                                         |
| `npm ci`                       | **8**  | No.                                                                                         |
| Lighthouse collections         | **12** | **Yes** — it is a measurement on a shared runner. 4 × `numberOfRuns: 3`.                    |
| `gh attestation verify`        | **3**  | No, and that is the point. See below.                                                       |
| axe / a11y                     | **1**  | Runs only inside `make package`, never as a gate.                                           |

End to end, one change reaching production runs **39 jobs** (41 when it touches
`infra/**` or the `Makefile`):

| Event                  | Jobs                                                                        |     |
| ---------------------- | --------------------------------------------------------------------------- | --- |
| feature pull request   | ci, lighthouse, dependency-review, osv-scan, gitleaks, actions-lock, lychee | 7   |
| merge → push `develop` | ci, lighthouse, codeql, osv-scan, gitleaks, actions-lock, release-please    | 7   |
| release pull request   | ci, lighthouse, dependency-review, osv-scan, gitleaks, actions-lock, lychee | 7   |
| merge → push `develop` | ci, lighthouse, codeql, osv-scan, gitleaks, actions-lock, release-please    | 7   |
| `release: published`   | package, ensure-test, deploy-test                                           | 3   |
| promote + approve      | promote, record                                                             | 2   |
| `record` → push `main` | ci, lighthouse, codeql, osv-scan, gitleaks, actions-lock                    | 6   |

The last row runs entirely after production is live, on a tree that has already
been through the same checks twice.

## Repetition that is deliberate

Four of the repetitions above are load-bearing. Collapsing them would be a
regression, so they are written down here rather than left to be rediscovered.

**`gh attestation verify` and `sha256sum -c`, in `package`, `deploy-test` and
`promote`.** The result is predictable; the point is _who_ is asking. Each
consumer verifies for itself instead of inheriting the previous stage's trust.
`SHA256SUMS` and `manifest.json` are Release assets too, so on their own they
prove only that three files agree with each other — an identity able to replace
the archive could replace all three. Only the signed provenance ties the archive
back to this repository's `release.yml`.

**`make ci`'s `hooks` target against the git hooks.** The same hooks run on the
same files, but the local run can be skipped: `--no-verify`, or a clone where
`make setup` was never run. CI is where that is caught.

**`ensure-test`'s no-op `tofu apply` on every release.** Reconciliation, not a
check. It is idempotent so that "the environment exists" needs no separate step
to remember, and the cost when nothing has changed is one plan and one DNS read.

**`monitor.yml` against `lighthouse.yml`.** Field measurement of the live site
versus a lab measurement of `dist/`. Different questions with the same tool.

The two smoke tests are also mirror images rather than duplicates:
`deploy-test` requires `X-Robots-Tag: noindex`, `promote` forbids it. Each
proves the right `host-config/` directory was selected.

## Gaps

Found while tracing the above, and listed here because they are the kind of
thing a map is for.

- **axe runs only at release time.** `make ci` is
  `hooks lint tf-fmt-check build test`, and `test` is unit + e2e. No workflow
  calls `make a11y`, so an accessibility regression merges freely and first
  fails when `make package` runs `report:a11y` — after the tag exists. The
  project's non-negotiables say a11y tests must not regress.
- **`npx serve` is an unpinned download.** Both Playwright configs use
  `webServer: npx serve dist`, and `serve` is in neither `package.json` nor
  `package-lock.json`, so it is fetched at test time on every e2e and a11y run.
  `release.yml` and `promote-prod.yml` argue against exactly this for the SWA
  CLI: a project dependency is tracked by Dependabot and seen by `osv-scan`,
  an ad-hoc `npx` download is neither.
- **Nothing consumes an artifact.** `ci`, `lighthouse` and `monitor` all call
  `upload-artifact`; `download-artifact` appears nowhere. `lighthouse` rebuilds
  the `dist` that `ci` just uploaded.
- **`report:lighthouse` asserts the budgets a second time.** `lhci autorun`
  includes `assert`, so packaging can fail a tagged release on a measurement
  that already passed as a required check on the same tree.
- **`monitor.yml`'s header check cannot fail** — warning-only, so it is a green
  check that reports nothing.
- **`ubuntu-latest` in five workflows** (security, secrets, lighthouse,
  linkcheck, monitor) against the pinned `ubuntu-24.04` everywhere else.
  `ci.yml` explains why the pin matters: the label is remapped on GitHub's
  schedule, not yours.
- **No `concurrency` group** on lighthouse, security, secrets or linkcheck, so
  rapid pushes stack instead of superseding.
- **The backend-config heredoc is duplicated** between `release.yml`'s
  `ensure-test` and `test-env.yml`, about thirty lines of identical shell in two
  workflow files — which is also the kind of logic the project constitution says
  belongs in a script.
- **`codeql`'s `autobuild` is a no-op** for `languages: javascript`.
- **`infra.yml`'s `paths:` filter does not include `scripts/test-env.sh`**, so a
  change to the script that drives `infra/test/` does not trigger infra
  validation.
