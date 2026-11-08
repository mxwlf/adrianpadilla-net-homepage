// Lighthouse CI configuration for the weekly production monitor
// (.github/workflows/monitor.yml). The lab run on pull requests uses
// lighthouserc.json and is unaffected by this file: lhci only auto-discovers
// `lighthouserc.{json,js,cjs,yml}`, so this one is reachable only through
// `--config`.
//
// WHY THIS FILE EXISTS, rather than monitor.yml passing --collect.url to the
// lab config: lighthouserc.json sets `collect.staticDistDir`, and that is not
// a setting a URL can override. In staticDistDir mode lhci serves the
// directory on a random port, then rewrites the port of every URL it was given
// onto its own server:
//
//     urls.forEach((rawUrl, i) => {
//       const url = new URL(rawUrl, 'http://localhost');
//       url.port = server.port.toString();   // <-- keeps the host, takes the port
//       urls[i] = url.href;
//     });
//     — node_modules/@lhci/cli/src/collect/collect.js
//
// So `--collect.url=https://adrianpadilla.net` became
// `https://adrianpadilla.net:32793/`, nothing answered there, and Lighthouse
// failed with NO_FCP ("the page did not paint any content"). That is what the
// monitor did on every run from 2026-08-03 to 2026-11-02 — fourteen
// consecutive red runs. Setting PROD_URL correctly does not fix it; only the
// absence of staticDistDir does, which is why `collect` is defined here from
// scratch rather than spread over the lab config's.
//
// `upload` is absent for the same reason it is not inherited: lhci runs the
// upload step only when it is configured
// (@lhci/cli/src/autorun/autorun.js), and the lab config targets
// `temporary-public-storage`, which would publish a weekly audit of production
// to a third-party bucket. The reports leave this job as its own build
// artifact instead.
const base = require("./lighthouserc.json");

// No fallback, for the reason recorded in monitor.yml: a monitor that silently
// audits the wrong host is worse than one that is obviously broken. The
// workflow checks this too, so that it fails before spending minutes in Chrome.
const url = process.env.PROD_URL;
if (!url) {
  throw new Error("PROD_URL is not set — the production monitor has no host to audit.");
}

module.exports = {
  ci: {
    collect: {
      url: [url],
      numberOfRuns: 3,
    },
    // Reused rather than restated: the budgets that gate a pull request are
    // the budgets production is held to, and a second copy would drift.
    // Measured against the live site on 2026-11-08 these pass, with
    // `legacy-javascript` and `render-blocking-insight` as warnings.
    assert: base.ci.assert,
  },
};
