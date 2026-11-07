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

Six automated trigger points, plus the hooks on your own machine. The two that
matter most are the ends: a pull request, where everything is gated, and a
manual dispatch, where production is reached.

```
 local            pull_request       push develop      release:published    dispatch + approval
─────────────────────────────────────────────────────────────────────────────────────────────────
 pre-commit       ci            *    ci                package              promote
 commit-msg       lighthouse    *    codeql            ├─ ensure-test       └─ record ─▶ main
 make ci (hand)   dependency-   *    osv-scan          └─ deploy-test                    (no jobs)
                  review             gitleaks
                  osv-scan      *    infra (paths)     test.adrianpadilla   adrianpadilla.net
                  gitleaks      *    release-please    .net — no reviewer,   — approval required,
                  actions-lock                         so it just goes       and no automatic
                  infra (paths)                                              path reaches here
                  lychee

 workflow_dispatch, on its own:  test-env  (teardown | restore | status)

 weekly:  codeql + osv-scan (Mon 04:17)   gitleaks (Sun 03:41)   lychee (Tue 02:13)
          actions-lock (Wed 05:29)        monitor: prod Lighthouse + headers (Mon 06:00)
          dependabot: npm, actions (7-day cooldown on actions)

 * = required status check on both develop-protection and main-protection
```

Two things about the shape of that table are deliberate, and both were once the
other way round.

**Nothing runs on a push to `main`.** `record` advancing `main` does re-enter
the pipeline — it pushes with a GitHub App token, and unlike `GITHUB_TOKEN`
that starts workflows, which is the same mechanism `release-please.yml` depends
on. Six jobs used to fire there: the full pull-request suite, against a tree
that had already passed it twice and was by then already serving production
traffic. No `push: [main]` trigger remains in any workflow.

**`lighthouse` and `actions-lock` run on pull requests only.** The gate is the
pull request; a second run on the merge commit asks the same question of the
same bytes. `actions-lock` gained a weekly schedule in exchange, because it is
the one check whose answer changes without the tree changing — a tag moved onto
different code, a repository renamed or taken over.

## What triggers what

| Workflow             | Trigger                                            | Jobs                                      |
| -------------------- | -------------------------------------------------- | ----------------------------------------- |
| `ci.yml`             | `pull_request`, push `develop`                     | `ci`                                      |
| `lighthouse.yml`     | `pull_request`                                     | `lighthouse`                              |
| `security.yml`       | `pull_request`, push `develop`, weekly             | `dependency-review`, `codeql`, `osv-scan` |
| `secrets.yml`        | `pull_request`, push `develop`, weekly             | `gitleaks`                                |
| `actions-lock.yml`   | `pull_request`, weekly                             | `actions-lock`                            |
| `infra.yml`          | `pull_request` + push `develop`, `paths:` filtered | `infra`                                   |
| `linkcheck.yml`      | `pull_request`, weekly                             | `lychee`                                  |
| `release-please.yml` | push `develop`                                     | `release-please`                          |
| `release.yml`        | `release: published`                               | `package` → `ensure-test` → `deploy-test` |
| `promote-prod.yml`   | `workflow_dispatch` **only**                       | `promote` → `record`                      |
| `test-env.yml`       | `workflow_dispatch` **only**                       | `test-env`                                |
| `monitor.yml`        | weekly                                             | `lighthouse`, `security-headers`          |

`ci`, `codeql`, `osv-scan` and `gitleaks` keep their push trigger on `develop`,
and that is not an oversight about identical trees. Admins are bypass actors on
both rulesets with `bypass_mode: "pull_request"`, so a pull request can be
merged with a required check red or with a stale head — on a repository with one
maintainer that is a real path, not a hypothetical one. The push run is the only
thing that would notice. `codeql` and `osv-scan` have a second reason: code
scanning results belong to the default branch, which is `develop`.

Two jobs are deliberately **not** required checks, for reasons that are easy to
undo by accident:

- `infra` has a `paths:` filter. A required check that does not run on every
  pull request is never reported, and GitHub waits on it forever.
- `codeql` excludes pull requests with an `if:`, and GitHub reports a skipped
  job as successful — a required check that is always green.

`actions-lock` has neither problem. It runs unconditionally on every pull
request and is not required either; its own header comment says it was written
that way so it _could_ be required. Making it required is a one-line change to
both rulesets followed by `make rulesets-apply`.

## Inventory

`make` and `npm` targets are expanded, because that is where the work is.

### `ci` — ci.yml, the gate

checkout · setup-node (npm cache) · setup-python 3.14 · setup-opentofu 1.13.8 ·
cache `~/.cache/pre-commit` · `npm ci` · `playwright install --with-deps chromium`
· **`make ci`** · upload `dist` artifact

`make ci` is `hooks lint tf-fmt-check build lint-html test a11y`:

| Step           | Commands                                                                                                                                                                                                                                                                                   |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `hooks`        | `pre-commit run --all-files` — 12 hooks: sync-pre-commit-deps, trailing-whitespace, end-of-file-fixer, check-yaml, check-added-large-files, check-case-conflict, check-illegal-windows-names, check-merge-conflict, detect-private-key, fix-byte-order-marker, mixed-line-ending, gitleaks |
| `lint`         | `prettier . --check` · `eslint .` · `stylelint src/assets/css/**/*.css`                                                                                                                                                                                                                    |
| `tf-fmt-check` | `tofu fmt -recursive -check -diff infra`                                                                                                                                                                                                                                                   |
| `build`        | `rm -rf dist` · `eleventy` · `scripts/generate-sitemap.mjs`                                                                                                                                                                                                                                |
| `lint-html`    | `html-validate dist/**/*.html`                                                                                                                                                                                                                                                             |
| `test`         | `node --test` · `playwright test` (serves `dist` on :4173)                                                                                                                                                                                                                                 |
| `a11y`         | `playwright test -c playwright.a11y.config.ts` — axe-core (serves `dist` on :4174)                                                                                                                                                                                                         |

The order matters: `build` populates `dist/`, and the three steps after it read
it. `lint-html` is separate from `build` so that validation happens once per
tree rather than once per build, and `a11y` is in this list rather than only in
`make package`, so an accessibility regression fails on the pull request that
introduces it instead of while packaging the release that contains it.

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

| Step                | Commands                                                                                                                                                                    |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `reports` → `build` | the same `rm -rf dist` · `eleventy` · sitemap as `make ci`                                                                                                                  |
| `reports`           | `rm -rf reports` · `report:html` (html-validate, JSON) · `report:e2e` (Playwright, JSON) · `report:a11y` (axe, JSON) · `report:lighthouse` (`lhci collect` + `lhci upload`) |
| `sbom`              | `cyclonedx-npm` → `sbom/bom.cdx.json`                                                                                                                                       |
| assembly            | `release-package.mjs`: `site/` (minus `staticwebapp.config.json`), `host-config/{prod,test}/`, `reports/`, `sbom/`, `SHA256SUMS` over `site/`+`sbom/`, `manifest.json`      |
| verify              | `sha256sum -c SHA256SUMS`                                                                                                                                                   |

`report:lighthouse` collects and uploads but does **not** assert. It was
`lhci autorun`, which includes `assert`, so packaging re-graded the budgets that
the required `lighthouse` check had already passed on the same tree — and could
fail a tagged release on a measurement that varies between runs. The reports
still travel with the artifact; the verdict belongs to the pull request.

### `ensure-test` — release.yml

checkout the tag · setup-opentofu · azure/login (test identity, OIDC) · write
`infra/test/backend.config` and `terraform.tfvars` from repository variables ·
**`make test-env-restore`** → `scripts/test-env.sh restore`:

`tofu init` · read `default_host_name` from state and the binding's state from
`az staticwebapp hostname show` · if the app is up, the CNAME matches and the
binding reads `Ready`, one reconciling `tofu apply` and stop · otherwise
`tofu apply` · `az network dns record-set cname set-record` pointing
`test.adrianpadilla.net` at the new `*.azurestaticapps.net` hostname · poll the
authoritative record until it reads back · `az staticwebapp hostname set
--validation-method cname-delegation --no-wait` · poll
`az staticwebapp hostname show` until the certificate reports `Ready`

The binding is made with `az` rather than by OpenTofu because the provider polls
a subscription-level operation status after creating one, and the test identity
stops at its resource group. `--no-wait` issues the same PUT without the poll.
That is also why the restore is one apply: with the binding out of the
configuration there is a single resource left, so the ordering lives in the
script instead of in `-target`. See `docs/deployment.md`.

It shares `concurrency: test-env` with `test-env.yml` so a dispatched teardown
cannot land in the middle of that sequence.

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
`main` after `record`. That is the measuring stick — work counted across those
four events is work done twice or more on the same bytes.

The `Was` column is what each number was before the triggers were pruned, kept
because it is the evidence for why they were.

| Work                           | Runs  | Was | Can the result differ?                                                                      |
| ------------------------------ | ----- | --- | ------------------------------------------------------------------------------------------- |
| `eleventy` build + sitemap     | **4** | 7   | No. `make build` starts with `rm -rf dist` precisely so output is a function of the commit. |
| `html-validate` over `dist/**` | **3** | 8   | No. It left `build` and became `lint-html`, so it runs per tree, not per build.             |
| Playwright e2e                 | **3** | 4   | Only by flake (2 retries in CI).                                                            |
| axe / a11y                     | **3** | 1   | Only by flake. It is a gate now; it used to run only while packaging.                       |
| `pre-commit run --all-files`   | **2** | 3   | No.                                                                                         |
| `tofu fmt -check`              | **2** | 3   | No.                                                                                         |
| `npm ci`                       | **5** | 8   | No.                                                                                         |
| Lighthouse collections         | **6** | 12  | **Yes** — it is a measurement on a shared runner. `numberOfRuns: 3`, now twice not 4×.      |
| `gh attestation verify`        | **3** | 3   | No, and that is the point. See below.                                                       |

End to end, one change reaching production runs **29 jobs**, down from 39 (31
and 41 when it touches `infra/**` or the `Makefile`):

| Event                  | Jobs                                                                        |     |
| ---------------------- | --------------------------------------------------------------------------- | --- |
| feature pull request   | ci, lighthouse, dependency-review, osv-scan, gitleaks, actions-lock, lychee | 7   |
| merge → push `develop` | ci, codeql, osv-scan, gitleaks, release-please                              | 5   |
| release pull request   | ci, lighthouse, dependency-review, osv-scan, gitleaks, actions-lock, lychee | 7   |
| merge → push `develop` | ci, codeql, osv-scan, gitleaks, release-please                              | 5   |
| `release: published`   | package, ensure-test, deploy-test                                           | 3   |
| promote + approve      | promote, record                                                             | 2   |
| `record` → push `main` | —                                                                           | 0   |

The ten jobs that went were not checks anyone had decided to run at those
points; they were the default `push: [main, develop]` trigger repeated across
five workflow files. Two gates were added in the same change — `a11y` on every
pull request, `actions-lock` weekly — so coverage went up while the job count
went down.

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

## Still open

Found while tracing the above and deliberately left alone, each with the reason.

- **`lighthouse` still builds `dist/` itself**, and nothing consumes the `dist`
  artifact `ci` uploads — `download-artifact` appears in no workflow. The
  obvious fix is the wrong one: within a workflow, reusing the artifact means
  `needs: ci`, which puts a required check behind the slowest job and delays the
  signal by minutes to save about one minute of CPU. The duplicate build buys
  parallelism. Leave it until the build is slow enough for the trade to flip.
- **`ensure-test` waits for `package`** although it needs nothing from it. The
  sequencing is deliberate — do not rebuild an environment for a release that
  cannot be packaged — but it does serialise a DNS and certificate wait behind
  four minutes of packaging. Running them in parallel with
  `deploy-test: needs: [package, ensure-test]` unchanged would be safe and
  faster; it was left out of the trigger pruning because it is a different kind
  of change.
- **`monitor.yml`'s header check cannot fail** — it emits `::warning::` only, so
  it is a green check that reports nothing. Making it fail is a one-line change,
  but it would start paging on production drift, which is a decision rather than
  a cleanup.
- **The backend-config heredoc is duplicated** between `release.yml`'s
  `ensure-test` and `test-env.yml`: about thirty lines of identical shell in two
  workflow files, which is also the kind of logic the project constitution says
  belongs in a script. Worth extracting to `scripts/`; it touches the deploy
  path, so it wants its own change.
- **`ubuntu-latest` in five workflows** (security, secrets, lighthouse,
  linkcheck, monitor) against the pinned `ubuntu-24.04` everywhere else.
  `ci.yml` explains why the pin matters: the label is remapped on GitHub's
  schedule, not yours.
- **No `concurrency` group** on lighthouse, security, secrets or linkcheck, so
  rapid pushes stack instead of superseding.
- **`actions-lock` is not a required check**, though it runs on every pull
  request and its own comment says it was written to be one.
- **`codeql`'s `autobuild` is a no-op** for `languages: javascript`.
- **`lighthouse.yml` uploads to `temporary-public-storage`** on every pull
  request, which publishes a report of the built site to an unlisted public URL.
  Harmless for a public site; worth knowing it happens.
