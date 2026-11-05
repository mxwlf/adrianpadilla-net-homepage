---
paths:
  - "src/**"
---

# Security rules

- Response headers, including the Content Security Policy, live in the committed `staticwebapp.config.json`. That file is the single source both environments derive from at packaging time (`scripts/release-package.mjs`), so a header change cannot reach one environment and not the other. Default the CSP to `default-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'`. Do not add a per-environment override: the only sanctioned difference is `X-Robots-Tag: noindex, nofollow` on the test host.
- No inline `<script>` or `<style>` tags; all JS and CSS must be in external files.
- Security headers are required: `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy`.
  - **Known gap, not yet closed:** `staticwebapp.config.json` currently sets only `Permissions-Policy`, `Strict-Transport-Security` and `Content-Security-Policy`. `X-Content-Type-Options` and `Referrer-Policy` are absent, and `Strict-Transport-Security` is still the trial value `max-age=300` rather than a production lifetime. `X-Frame-Options` is covered in effect by the CSP's `frame-ancestors 'none'`. Closing this changes live response headers, so it belongs in its own change with its own verification — not folded into unrelated work. Until then, `monitor.yml`'s header check reports the two missing ones.
- Never commit secrets, API keys, or credentials; use environment variables.
- Dependency changes must pass `dependency-review-action` (fail on severity >= high).
- CodeQL and OSV scanning must remain enabled; do not disable security workflows.
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
