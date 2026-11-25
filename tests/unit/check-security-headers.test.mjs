import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const SCRIPT = new URL("../../scripts/check-security-headers.sh", import.meta.url).pathname;

// What production serves today, as `curl -I` prints it.
const GOOD = [
  "HTTP/2 200",
  "content-type: text/html",
  "x-content-type-options: nosniff",
  "x-frame-options: DENY",
  "content-security-policy: default-src 'self'",
  "permissions-policy: camera=()",
  "referrer-policy: same-origin",
  "strict-transport-security: max-age=2592001; includeSubDomains",
];

function check(lines) {
  const file = join(mkdtempSync(join(tmpdir(), "headers-")), "headers.txt");
  writeFileSync(file, lines.join("\r\n") + "\r\n");
  const { status, stdout } = spawnSync("bash", [SCRIPT, "--headers", file], { encoding: "utf8" });
  return { status, stdout };
}

describe("check-security-headers.sh", () => {
  it("check_WhenEveryHeaderIsServedOnce_ThenPasses", () => {
    const { status, stdout } = check(GOOD);
    assert.equal(status, 0, stdout);
  });

  it("check_WhenADeclaredHeaderIsSentTwiceWithTheSameValue_ThenPassesWithANotice", () => {
    const { status, stdout } = check([...GOOD, "X-Content-Type-Options: nosniff"]);
    assert.equal(status, 0, stdout);
    assert.match(stdout, /::notice::X-Content-Type-Options sent 2 identical times/);
  });

  it("check_WhenCopiesOfAHeaderDisagree_ThenFails", () => {
    const { status, stdout } = check([...GOOD, "referrer-policy: unsafe-url"]);
    assert.equal(status, 1, stdout);
    assert.match(stdout, /\[FAIL\] Referrer-Policy sent 2 times with different values/);
  });

  it("check_WhenAWeakerHstsCopyComesFirst_ThenFails", () => {
    // Browsers enforce the first HSTS copy, so reading only the last one would pass this.
    const { status, stdout } = check([
      "HTTP/2 200",
      "strict-transport-security: max-age=300",
      ...GOOD.slice(1),
    ]);
    assert.equal(status, 1, stdout);
    assert.match(stdout, /\[FAIL\] Strict-Transport-Security sent 2 times with different values/);
  });

  it("check_WhenARequiredHeaderIsMissing_ThenFails", () => {
    const { status, stdout } = check(
      GOOD.filter((line) => !line.startsWith("x-content-type-options"))
    );
    assert.equal(status, 1, stdout);
    assert.match(stdout, /\[FAIL\] X-Content-Type-Options absent/);
  });

  it("check_WhenTheResponseIsNot200_ThenFailsWithoutJudgingHeaders", () => {
    const { status, stdout } = check(["HTTP/2 404", ...GOOD.slice(1)]);
    assert.equal(status, 1, stdout);
    assert.match(stdout, /returned HTTP 404/);
    assert.doesNotMatch(stdout, /\[PASS\]/);
  });
});
