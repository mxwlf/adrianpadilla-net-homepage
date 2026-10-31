// analytics.js — Google Analytics 4 bootstrap (gtag.js).
//
// This is Google's standard gtag snippet, with two changes.
//
// 1. Google publishes the bootstrap as an inline <script>, and this site
//    forbids those (see .claude/rules/security.md) because the enforced CSP has
//    no 'unsafe-inline' in script-src. Keeping it in a file means no CSP hash
//    or nonce to maintain.
// 2. The `config` command only runs for real visits to the live site, so the
//    development loop stops measuring itself. See shouldMeasure below.
//
// The loader (<script src=".../gtag/js?id=...">) is emitted next to this tag in
// layouts/base.njk, so every page is instrumented. Load order does not matter:
// gtag.js takes over window.dataLayer and drains whatever is already queued.
// That loader stays unconditional even where this gate says no: a GA4 page_view
// comes from the `config` command, not from fetching gtag.js, and keeping the
// tag in every build is what lets the Lighthouse budgets measure the same page
// production serves (see .claude/rules/performance.md).
//
// The measurement id and the canonical site URL arrive on this tag's data-
// attributes, so both stay declared once, in src/_data/site.json.

// Whether this page view is real traffic to the live site, rather than a
// developer or a build gate driving a browser over a local `dist`. Every one of
// those loads this exact HTML, so without a gate `make ci`, `npm run dev` and
// Lighthouse all land in the property as page views:
//
//   - host:       excludes localhost (the dev server, `serve dist`, Lighthouse's
//                 static server) and any preview host that is not the real one.
//   - webdriver:  excludes Playwright — both `npm run test:e2e` and
//                 `npm run test:a11y` — and other automation, which set this on
//                 every page they drive.
//   - user agent: excludes Lighthouse and headless Chrome, the case the host
//                 check cannot catch: .github/workflows/monitor.yml points
//                 Lighthouse at the production URL on a schedule.
function shouldMeasure(location, navigator, siteUrl) {
  if (!siteUrl) return false;

  const siteHost = new URL(siteUrl).host;
  if (location.host !== siteHost && location.host !== `www.${siteHost}`) return false;

  if (navigator.webdriver) return false;

  return !/\b(Chrome-Lighthouse|HeadlessChrome)\b/.test(navigator.userAgent);
}

const tag = document.currentScript;
const measurementId = tag?.dataset.measurementId;
const siteUrl = tag?.dataset.siteUrl;

// Initialised unconditionally: gtag.js expects to find a queue, and an empty one
// is the whole point when the gate says no.
window.dataLayer = window.dataLayer || [];
function gtag() {
  window.dataLayer.push(arguments);
}

if (measurementId && shouldMeasure(window.location, window.navigator, siteUrl)) {
  gtag("js", new Date());
  gtag("config", measurementId);
}
