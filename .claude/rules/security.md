---
paths:
  - "src/**"
---

# Security rules

- Content Security Policy (CSP) must be configured in the hosting provider's `_headers` file; default to `default-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'`.
- No inline `<script>` or `<style>` tags; all JS and CSS must be in external files.
- Security headers are required: `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy`.
- Never commit secrets, API keys, or credentials; use environment variables.
- Dependency changes must pass `dependency-review-action` (fail on severity >= high).
- CodeQL and OSV scanning must remain enabled; do not disable security workflows.
- Pin third-party GitHub Actions to full commit SHAs in CI workflows.
