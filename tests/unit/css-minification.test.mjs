import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

import { minifyCss } from "../../eleventy.config.js";

// These tests exist because `make ci` does not run Lighthouse -- the lighthouse
// job is separate and slower, so the gate that every push has to pass cannot
// see a Lighthouse budget regression. Minification is what keeps the
// `unminified-css` audit quiet, and #75 showed how quietly that can break: the
// audit ignores an unminified stylesheet only while its estimated savings stay
// under a hard-coded 2048 bytes, so adding comments to the source was enough to
// turn the job red with no local signal at all.
//
// Asserting the invariant here means the cheap gate catches it instead.
const SOURCE = readFileSync(new URL("../../src/assets/css/main.css", import.meta.url), "utf8");

describe("CSS minification", () => {
  const minified = minifyCss(SOURCE);

  it("strips the comments the source is full of", () => {
    assert.ok(SOURCE.includes("/*"), "precondition: the source is commented");
    assert.ok(!minified.includes("/*"), "minified CSS must carry no comments");
  });

  it("collapses the stylesheet onto one line", () => {
    assert.ok(!minified.includes("\n"), "minified CSS must carry no newlines");
  });

  // Lighthouse's unminified-css audit ignores a stylesheet whose estimated
  // savings are under 5% of its size. Comments and whitespace were 47% of this
  // file, so the margin here is what the budget actually rests on.
  it("leaves well under Lighthouse's 5% waste threshold", () => {
    const waste = 1 - minified.replace(/\s+/g, "").length / minified.length;
    assert.ok(waste < 0.05, `minified waste ${(waste * 100).toFixed(2)}% must stay under 5%`);
  });

  it("keeps the theme overrides after the :root defaults they override", () => {
    // The dark theme works by re-declaring tokens later in the cascade. A
    // minifier that merged or reordered rules would silently invert the
    // themes, which no contrast assertion would attribute to the build.
    const rootDefault = minified.indexOf("--color-text-muted:#6b6b6b");
    const darkPreference = minified.indexOf("prefers-color-scheme:dark");
    const darkOverride = minified.lastIndexOf("--color-text-muted:#ccc");

    assert.ok(rootDefault >= 0, "the :root value must survive minification");
    assert.ok(darkPreference > rootDefault, "the dark media query must follow :root");
    assert.ok(darkOverride > darkPreference, "the dark override must follow the media query");
  });

  it("preserves declarations verbatim", () => {
    assert.match(minified, /\.footer-version\{[^}]*font-size:10px/);
    assert.match(minified, /\.footer-version\{[^}]*color:var\(--color-text-muted\)/);
  });
});
