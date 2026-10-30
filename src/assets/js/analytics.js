// analytics.js — Google Analytics 4 bootstrap (gtag.js).
//
// This is Google's standard gtag snippet, with one change: Google publishes the
// bootstrap as an inline <script>, and this site forbids those (see
// .claude/rules/security.md) because the enforced CSP has no 'unsafe-inline' in
// script-src. Keeping it in a file means no CSP hash or nonce to maintain.
//
// The loader (<script src=".../gtag/js?id=...">) is emitted next to this tag in
// layouts/base.njk, so every page is instrumented. Load order does not matter:
// gtag.js takes over window.dataLayer and drains whatever is already queued.
//
// The measurement id arrives on this tag's data-measurement-id attribute, so it
// stays declared once, in src/_data/site.json.
const measurementId = document.currentScript?.dataset.measurementId;

window.dataLayer = window.dataLayer || [];
function gtag() {
  window.dataLayer.push(arguments);
}

if (measurementId) {
  gtag("js", new Date());
  gtag("config", measurementId);
}
