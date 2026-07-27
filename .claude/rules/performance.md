---
paths:
  - "src/**/*.{html,njk,css,js,md}"
---

# Performance rules

- Prefer server-rendered HTML; avoid client-side rendering frameworks.
- Images must include width/height; use srcset/sizes for responsive images when relevant.
- Keep total JS under 20KB gzipped unless justified.
- Lighthouse CI performance budget must remain >= 0.90.
- Use `loading="lazy"` on below-the-fold images; reserve explicit dimensions to avoid CLS.
- CSS must be minimal and avoid unused rules; no CSS frameworks unless justified.
- Scripts must use `defer` or `async`; no render-blocking JS in `<head>`.
- Self-host third-party assets for CSP simplicity and reduced external requests.
