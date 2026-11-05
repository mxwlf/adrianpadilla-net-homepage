import { test, expect } from "@playwright/test";
import { readFileSync } from "node:fs";

// The expectation comes from version.txt rather than a literal, so the test
// does not need editing on every release -- and it fails if the footer ever
// stops tracking the file release-please maintains.
const VERSION = readFileSync(new URL("../../version.txt", import.meta.url), "utf8").trim();

test.describe("Footer version", () => {
  test("the homepage shows the released version", async ({ page }) => {
    await page.goto("/");
    await expect(page.locator(".footer-version")).toHaveText(`Version ${VERSION}`);
  });

  // The footer is a shared partial, so this is really asserting that nothing
  // conditionalised it onto the homepage alone.
  test("every page shows it, not just the homepage", async ({ page }) => {
    for (const path of ["/", "/about/", "/about/me/", "/404.html"]) {
      await page.goto(path);
      await expect(page.locator(".footer-version")).toContainText(VERSION);
    }
  });

  test("it is spelled out, so it reads correctly aloud", async ({ page }) => {
    await page.goto("/");
    // Asserted on the anchor rather than the paragraph: the anchor's text is
    // what a screen reader announces as the link, and the paragraph now carries
    // the surrounding whitespace that a regex expectation would have to allow
    // for. "Version 1.0.1", not a bare "v1.0.1" needing a hidden label.
    await expect(page.locator(".footer-version a")).toHaveText(/^Version \d+\.\d+\.\d+/);
  });

  test("the copyright line is still intact beside it", async ({ page }) => {
    await page.goto("/");
    await expect(page.locator(".footer-text")).toContainText("All rights reserved");
  });

  // The link checker excludes this repository's releases/tag/ URLs, because in
  // a release pull request the tag does not exist yet. That exclusion means a
  // typo in site.repository would not be caught there, so it is caught here
  // instead -- this assertion is the only thing guarding the href.
  test("the version links to its own release notes", async ({ page }) => {
    await page.goto("/");
    const link = page.locator(".footer-version a");
    await expect(link).toHaveAttribute(
      "href",
      `https://github.com/mxwlf/adrianpadilla-net-homepage/releases/tag/v${VERSION}`
    );
    await expect(link).toHaveText(`Version ${VERSION}`);
  });

  test("the link is reachable by keyboard and has a visible focus ring", async ({ page }) => {
    await page.goto("/");
    const link = page.locator(".footer-version a");
    await link.focus();
    await expect(link).toBeFocused();
  });

  test("it survives with JavaScript disabled", async ({ browser }) => {
    const context = await browser.newContext({ javaScriptEnabled: false });
    const page = await context.newPage();
    await page.goto("/");
    await expect(page.locator(".footer-version")).toContainText(VERSION);
    await context.close();
  });
});
