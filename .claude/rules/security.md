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
- Pin third-party GitHub Actions to full commit SHAs in CI workflows. This is **enforced by GitHub**, not by review: the repository has the "require actions to be pinned to a full-length commit SHA" policy active, so a workflow referencing a tag or branch is refused at the `Set up job` step with `the actions … are not allowed … because all actions must be pinned to a full-length commit SHA`. Keep the version in a trailing comment (`@<sha> # v7`) — Dependabot reads that convention and updates the SHA and the comment together. Verify the policy with:

  ```sh
  gh api repos/mxwlf/adrianpadilla-net-homepage/actions/permissions --jq .sha_pinning_required
  ```
