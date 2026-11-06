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
- **Comment the stylesheet freely — the build minifies it.** `eleventy.config.js`
  runs `src/assets/css/*.css` through clean-css before fingerprinting, so source
  comments cost nothing at runtime and the filename hash still describes the
  bytes actually served. This is not cosmetic: Lighthouse's `unminified-css`
  audit ignores an unminified stylesheet only while its estimated savings stay
  under a hard-coded 2048 bytes, and the file used to sit ~150 bytes under that
  cliff, so one added comment turned the lighthouse job red. `make ci` does not
  run Lighthouse, so `tests/unit/css-minification.test.mjs` asserts the
  invariant where the cheap gate can see it.
- Scripts must use `defer` or `async`; no render-blocking JS in `<head>`.
- Self-host third-party assets for CSP simplicity and reduced external requests.

## Justified exceptions

Approved departures from the rules above. Each one names the gate it relaxes,
so the next person does not have to guess whether a red check is expected.

- **Google Analytics (`gtag.js`)** — the layout loads Google's tag on every
  page. It is ~172KB transferred (~55KB gzipped), of which ~73KB never executes
  on a page view, so it exceeds the 20KB JS budget and trips the
  `lighthouse:no-pwa` preset's zero-tolerance `unused-javascript` assertion. The
  file is third-party, already minified, and not self-hostable in practice:
  Google serves one bundle for every tag product and updates it continuously.
  `lighthouserc.json` therefore allows `unused-javascript` a `maxLength` of 1.
  It stays error-level, so a _second_ offender — including any of our own JS —
  still fails the gate. Lighthouse category scores are unaffected; performance,
  accessibility, best-practices and SEO all remain at 1.00.
