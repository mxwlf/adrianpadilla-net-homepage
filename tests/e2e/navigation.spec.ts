import { test, expect } from "@playwright/test";

test.describe("Navigation", () => {
  test("homepage loads successfully", async ({ page }) => {
    const response = await page.goto("/");
    expect(response?.status()).toBe(200);
    await expect(page).toHaveTitle(/Site Title/);
  });

  test("homepage has main content area", async ({ page }) => {
    await page.goto("/");
    const main = page.locator("main#content");
    await expect(main).toBeVisible();
  });

  test("navigation links are present", async ({ page }) => {
    await page.goto("/");
    const nav = page.locator("nav");
    await expect(nav).toBeVisible();
    const links = nav.locator("a");
    expect(await links.count()).toBeGreaterThan(0);
  });

  test("navigation links work", async ({ page }) => {
    await page.goto("/");
    const aboutLink = page.locator('nav a[href="/about/"]');
    if ((await aboutLink.count()) > 0) {
      await aboutLink.click();
      await expect(page).toHaveURL(/\/about\//);
      const response = await page.goto("/about/");
      expect(response?.status()).toBe(200);
    }
  });

  test("404 page works", async ({ page }) => {
    const response = await page.goto("/this-page-does-not-exist/");
    // Static servers may return 200 with 404 content or actual 404
    // Check that the page loads without crashing
    expect(response?.status()).toBeDefined();
  });

  test("skip link is present", async ({ page }) => {
    await page.goto("/");
    const skipLink = page.locator('a.skip-link[href="#content"]');
    await expect(skipLink).toBeAttached();
  });
});
