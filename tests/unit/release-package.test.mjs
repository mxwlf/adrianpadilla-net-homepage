import { describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  buildManifest,
  hostConfigVariants,
  renderSha256Sums,
} from "../../scripts/release-package.mjs";

// A trimmed stand-in for staticwebapp.config.json: enough shape to prove the
// variants are derived from the real file rather than hand-maintained copies.
const BASE_CONFIG = {
  routes: [
    { route: "/assets/*", headers: { "cache-control": "public, max-age=31536000, immutable" } },
  ],
  globalHeaders: {
    "Strict-Transport-Security": "max-age=300; includeSubDomains",
    "Content-Security-Policy": "default-src 'self'; object-src 'none';",
  },
};

describe("host config variants", () => {
  it("ships production byte-for-byte as the committed base config", () => {
    const { prod } = hostConfigVariants(BASE_CONFIG);
    assert.deepEqual(prod, BASE_CONFIG);
  });

  it("adds a noindex robots header to the test variant only", () => {
    const { prod, test } = hostConfigVariants(BASE_CONFIG);

    assert.equal(test.globalHeaders["X-Robots-Tag"], "noindex, nofollow");
    assert.ok(!("X-Robots-Tag" in prod.globalHeaders), "production must stay indexable");
  });

  // The whole point of deriving both from one file: a CSP or HSTS change lands
  // in test and prod together instead of drifting between two copies.
  it("carries every other base header into both variants unchanged", () => {
    const { prod, test } = hostConfigVariants(BASE_CONFIG);

    for (const variant of [prod, test]) {
      assert.equal(
        variant.globalHeaders["Content-Security-Policy"],
        BASE_CONFIG.globalHeaders["Content-Security-Policy"]
      );
      assert.equal(
        variant.globalHeaders["Strict-Transport-Security"],
        BASE_CONFIG.globalHeaders["Strict-Transport-Security"]
      );
      assert.deepEqual(variant.routes, BASE_CONFIG.routes);
    }
  });

  it("does not mutate the config it was handed", () => {
    const base = structuredClone(BASE_CONFIG);
    hostConfigVariants(base);
    assert.deepEqual(base, BASE_CONFIG);
  });
});

describe("SHA256SUMS rendering", () => {
  const ENTRIES = [
    { path: "site/index.html", sha256: "b".repeat(64) },
    { path: "sbom/bom.cdx.json", sha256: "a".repeat(64) },
  ];

  // Two spaces between hash and path is what `sha256sum -c` expects; one space
  // means "text mode" on some implementations and fails to parse on others.
  it("emits sha256sum -c compatible lines, sorted by path", () => {
    assert.equal(
      renderSha256Sums(ENTRIES),
      `${"a".repeat(64)}  sbom/bom.cdx.json\n${"b".repeat(64)}  site/index.html\n`
    );
  });

  it("ends with a newline so the file concatenates cleanly", () => {
    assert.ok(renderSha256Sums(ENTRIES).endsWith("\n"));
  });

  it("renders an empty manifest as an empty string", () => {
    assert.equal(renderSha256Sums([]), "");
  });
});

describe("release manifest", () => {
  const FIELDS = {
    version: "1.2.3",
    commit: "0123456789abcdef0123456789abcdef01234567",
    builtAt: "2026-11-04T12:00:00.000Z",
    nodeVersion: "v20.11.0",
    lockfileSha256: "c".repeat(64),
    siteSha256: "d".repeat(64),
  };

  it("records everything needed to trace a deployed artifact back to its build", () => {
    const manifest = buildManifest(FIELDS);

    for (const [key, value] of Object.entries(FIELDS)) {
      assert.equal(manifest[key], value, `manifest.${key}`);
    }
  });

  // The promote job verifies this before touching production, so a missing or
  // renamed digest field has to fail loudly here rather than at deploy time.
  it("rejects a manifest missing any required field", () => {
    for (const key of Object.keys(FIELDS)) {
      const incomplete = { ...FIELDS };
      delete incomplete[key];
      assert.throws(() => buildManifest(incomplete), new RegExp(key), `missing ${key} must throw`);
    }
  });
});
