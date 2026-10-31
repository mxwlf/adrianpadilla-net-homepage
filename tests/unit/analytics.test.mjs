import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createContext, runInContext } from "node:vm";

// analytics.js ships as a classic browser <script>, so a fresh VM context
// holding the handful of globals it touches is the entire harness — no bundler
// and no DOM implementation. This is also the only place the production path
// can be tested: the Playwright suites always run on localhost, under a
// webdriver, which is exactly what the gate refuses.
const SOURCE = readFileSync(new URL("../../src/assets/js/analytics.js", import.meta.url), "utf8");

const MEASUREMENT_ID = "G-TEST123456";
const SITE_URL = "https://adrianpadilla.net";
const BROWSER_UA =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36";

// Runs analytics.js against a stubbed browser and returns the commands it left
// in window.dataLayer, each as an array of strings (the real entries are
// `arguments` objects, which is what gtag.js drains).
function bootstrap({
  host = "adrianpadilla.net",
  userAgent = BROWSER_UA,
  webdriver = false,
  dataset = { measurementId: MEASUREMENT_ID, siteUrl: SITE_URL },
} = {}) {
  const window = {
    location: { host },
    navigator: { userAgent, webdriver },
  };

  runInContext(SOURCE, createContext({ window, document: { currentScript: { dataset } }, URL }));

  // Rebuilt with this realm's Array.from rather than mapped in place: the queue
  // is created inside the VM, and assert's deep equality compares prototypes,
  // which differ across realms.
  return Array.from(window.dataLayer, (entry) => Array.from(entry, (value) => String(value)));
}

describe("analytics bootstrap", () => {
  it("configures the property for a real visit to the production host", () => {
    const commands = bootstrap();

    assert.equal(commands.length, 2);
    assert.equal(commands[0][0], "js");
    assert.ok(!Number.isNaN(Date.parse(commands[0][1])), "the js command carries a timestamp");
    assert.deepEqual(commands[1], ["config", MEASUREMENT_ID]);
  });

  it("configures the property on the www host too", () => {
    const commands = bootstrap({ host: "www.adrianpadilla.net" });
    assert.ok(commands.some(([command, id]) => command === "config" && id === MEASUREMENT_ID));
  });

  // Everything below must leave gtag.js an initialised but empty queue: the
  // page_view comes from the `config` command, so withholding it is what keeps
  // the hit from being sent.
  it("measures nothing on a local development or preview host", () => {
    assert.deepEqual(bootstrap({ host: "localhost:4173" }), []);
    assert.deepEqual(bootstrap({ host: "127.0.0.1:8080" }), []);
    assert.deepEqual(bootstrap({ host: "wonderful-sky-0f46c841e.azurestaticapps.net" }), []);
  });

  it("measures nothing under browser automation, even on the production host", () => {
    assert.deepEqual(bootstrap({ webdriver: true }), []);
  });

  it("measures nothing for Lighthouse, even on the production host", () => {
    assert.deepEqual(bootstrap({ userAgent: `${BROWSER_UA} Chrome-Lighthouse` }), []);
  });

  it("measures nothing for headless Chrome", () => {
    assert.deepEqual(
      bootstrap({ userAgent: BROWSER_UA.replace("Chrome/", "HeadlessChrome/") }),
      []
    );
  });

  it("measures nothing when either data attribute is missing", () => {
    assert.deepEqual(bootstrap({ dataset: { siteUrl: SITE_URL } }), []);
    assert.deepEqual(bootstrap({ dataset: { measurementId: MEASUREMENT_ID } }), []);
  });
});
