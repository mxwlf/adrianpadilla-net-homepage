import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

import build from "../../src/_data/build.js";

// version.txt is maintained by release-please and committed, so it is the one
// place the released version is recorded. Reading it at build time -- rather
// than passing RELEASE_VERSION in -- is what makes a local build and the
// release build agree: release.yml checks out the tag, whose tree carries the
// bumped file.
const VERSION_TXT = readFileSync(new URL("../../version.txt", import.meta.url), "utf8");

describe("build-time global data", () => {
  it("exposes the version recorded in version.txt", () => {
    assert.equal(build.version, VERSION_TXT.trim());
  });

  it("exposes it without surrounding whitespace, so templates need no filter", () => {
    assert.equal(build.version, build.version.trim());
    assert.ok(build.version.length > 0, "version must not be empty");
  });

  it("looks like a semantic version", () => {
    assert.match(build.version, /^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$/);
  });

  it("still exposes the copyright year", () => {
    assert.equal(build.year, new Date().getFullYear());
  });
});
