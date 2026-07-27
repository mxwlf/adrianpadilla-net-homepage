---
paths:
  - "src/**"
---

# SEO rules

- Every page must have a unique `<title>` and `<meta name="description">`.
- Every page must include a `<link rel="canonical">` pointing to its canonical URL.
- Open Graph tags (`og:title`, `og:description`, `og:url`, `og:image`) are required on all public pages.
- A valid `sitemap.xml` must be generated at build time via `scripts/generate-sitemap.mjs`.
- `robots.txt` must reference the sitemap URL.
- Lighthouse SEO score must remain >= 0.95.
- Internal links must use relative paths or site-relative URLs; avoid hardcoded domains.
- Headings must follow a logical hierarchy (one `<h1>` per page, no skipped levels).
