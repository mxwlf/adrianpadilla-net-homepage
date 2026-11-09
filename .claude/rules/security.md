---
paths:
  - "src/**"
---

# Security rules

- Response headers, including the Content Security Policy, live in the committed `staticwebapp.config.json`. That file is the single source both environments derive from at packaging time (`scripts/release-package.mjs`), so a header change cannot reach one environment and not the other. Default the CSP to `default-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'`. Do not add a per-environment override: the only sanctioned difference is `X-Robots-Tag: noindex, nofollow` on the test host.
- No inline `<script>` or `<style>` tags; all JS and CSS must be in external files.
- Security headers are required: `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy`.
  - **What is actually served, measured rather than assumed.** `staticwebapp.config.json` declares `Permissions-Policy`, `Strict-Transport-Security`, `Content-Security-Policy` and `X-Frame-Options`, and Azure Static Web Apps adds two more of its own, so `curl -I` against either environment returns `x-content-type-options: nosniff` and `referrer-policy: same-origin` as well. Do not infer the served headers from the config file alone.
  - **`X-Frame-Options: DENY` is deliberately redundant.** The CSP's `frame-ancestors 'none'` already covers framing and a CSP-aware browser ignores `X-Frame-Options` by spec. It is declared anyway so that framing protection does not depend on one hand-maintained string staying correct — the same CSP line is already missing the `base-uri 'self'` this rule asks for, and lost it without being recorded. Do not remove it as duplicated. See @docs/hosting-setup.md.
  - **Two gaps remain, both narrower than the config file suggests:** `Strict-Transport-Security` is still the trial value `max-age=300` rather than a production lifetime, and the platform's `Referrer-Policy: same-origin` is not the `strict-origin-when-cross-origin` this rule asks for — declaring it in `globalHeaders` would override the default. Each of these changes live response headers, so each belongs in its own change with its own verification.
- Never commit secrets, API keys, or credentials; use environment variables.
- Dependency changes must pass `dependency-review-action` (fail on severity >= high).
- CodeQL and OSV scanning must remain enabled; do not disable security workflows.
- **Accepted dependency risk: `extract-zip` 2.0.1.** Two high Dependabot advisories
  — GHSA-7pqw-9j4j-h8q3 (arbitrary file write via symlink archive entries) and
  GHSA-jmr9-qjv8-65gv (unvalidated symlink path traversal) — are **dismissed as
  tolerable risk**, not fixed. Both report `first_patched_version: NONE`; 2.0.1 is
  the latest release and is vulnerable, so no version bump or `overrides` entry can
  clear them.

  The code path is unreachable here, which is the basis for accepting it:

  - `extract-zip` has exactly one call site in the whole tree —
    `@puppeteer/browsers/lib/cjs/install.js:233` → `unpackArchive()`, reached only
    from `install()`, the browser _download_ routine.
  - Nothing invokes it. `lighthouse` depends on `puppeteer-core`, which by design
    never downloads a browser; it lists the full `puppeteer` package (the one with
    the downloading postinstall) only in its own devDependencies, which npm does
    not install for us. Grepping `node_modules/lighthouse/` and `node_modules/@lhci/`
    for `@puppeteer/browsers` returns **zero files**.
  - What actually runs: `chrome-launcher` launches Chrome, and `puppeteer-core` is
    used for one line — `puppeteer.connect({browserURL})` in
    `lighthouse/core/gather/navigation-runner.js:283` — which attaches to an
    already-running browser over CDP.
  - It is a devDependency four levels deep (`@lhci/cli` → `lighthouse` →
    `puppeteer-core` → `@puppeteer/browsers`). The site itself has **zero runtime
    dependencies**, so none of this ships.

  Exploiting it would require handing an attacker-controlled zip to a function this
  project never calls. `osv-scan` and `dependency-review` both pass.

  **A working fix exists and was deliberately declined.**
  `"extract-zip": "npm:@electron-internal/extract-zip@^1.0.8"` — the official
  successor from the same repository — was tested end to end: it removes 7 packages,
  clears both alerts, and passes `make ci`, `npm run lighthouse` and a direct
  exercise of the real `unpackArchive()` path. It was rejected because it ships
  7.2 MB of **9 prebuilt native `.node` binaries** in a single tarball, which is a
  larger and less auditable supply-chain surface than the unreachable flaw it
  removes. Revisit if `@puppeteer/browsers` ever calls `install()` on our behalf, or
  if that package drops `extract-zip` upstream — at which point the override becomes
  unnecessary anyway.

- Every action the workflows use is pinned through **`.github/workflows/actions.lock`**, not through SHAs in `uses:` lines. Workflow files reference a full semver tag (`actions/checkout@v7.0.1`) and the lockfile records the commit it resolves to, plus the source repository's numeric `owner_id`/`repo_id`. Never edit the lockfile by hand.

  The lockfile supersedes SHA pinning and covers two things a SHA in a `uses:` line cannot:

  - **Transitive dependencies.** Actions used by your actions. `actions/attest-build-provenance` pulls in `actions/attest`, which no SHA pin in this repository ever reached.
  - **Repository identity.** A changed `owner_id` or `repo_id` means the repository behind that name is not the one that was locked — a rename or a takeover. Investigate before merging; this is the one lockfile change that is never routine.

  Regenerate after adding a workflow or changing any `uses:`, and let Dependabot handle version bumps — it updates the workflow reference and the lockfile entry in the same pull request:

  ```sh
  gh extension install github/gh-actions-lock   # once
  make actions-lock                             # regenerate
  make actions-lock-verify                      # what CI checks
  ```

  Two GitHub policies back this, both active, and a lockfile satisfies the first:

  ```sh
  gh api repos/mxwlf/adrianpadilla-net-homepage/actions/permissions --jq .sha_pinning_required
  ```

  See [`.github/rulesets/README.md`](../../.github/rulesets/README.md) for what each policy rejects and the surprises they cause.
