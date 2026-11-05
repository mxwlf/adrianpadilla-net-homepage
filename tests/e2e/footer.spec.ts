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
    // "Version 1.0.1", not a bare "v1.0.1" that needs a hidden label to make
    // sense to a screen reader.
    await expect(page.locator(".footer-version")).toHaveText(/^Version \d+\.\d+\.\d+/);
  });

  test("the copyright line is still intact beside it", async ({ page }) => {
    await page.goto("/");
    await expect(page.locator(".footer-text")).toContainText("All rights reserved");
  });

  test("it survives with JavaScript disabled", async ({ browser }) => {
    const context = await browser.newContext({ javaScriptEnabled: false });
    const page = await context.newPage();
    await page.goto("/");
    await expect(page.locator(".footer-version")).toContainText(VERSION);
    await context.close();
  });
});
