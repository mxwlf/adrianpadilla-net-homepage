import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

test.describe("Accessibility", () => {
  test("homepage has no a11y violations", async ({ page }) => {
    await page.goto("/");

    const results = await new AxeBuilder({ page }).analyze();

    expect(results.violations).toEqual([]);
  });

  test("about page has no a11y violations", async ({ page }) => {
    const response = await page.goto("/about/");
    // Only run a11y check if the page exists
    if (response?.status() === 200) {
      const results = await new AxeBuilder({ page }).analyze();
      expect(results.violations).toEqual([]);
    }
  });

  test("skip link exists and points to main content", async ({ page }) => {
    await page.goto("/");

    const skipLink = page.locator('a.skip-link[href="#content"]');
    await expect(skipLink).toBeAttached();

    // Verify the target element exists
    const mainContent = page.locator("main#content");
    await expect(mainContent).toBeAttached();
  });

  test("skip link becomes visible on focus", async ({ page }) => {
    await page.goto("/");

    // Tab to the skip link
    await page.keyboard.press("Tab");
    const skipLink = page.locator("a.skip-link");
    await expect(skipLink).toBeFocused();
    await expect(skipLink).toBeVisible();
  });

  test("heading hierarchy is correct", async ({ page }) => {
    await page.goto("/");

    // Get all headings
    const headings = await page.locator("h1, h2, h3, h4, h5, h6").all();

    if (headings.length > 0) {
      // First heading should be h1
      const firstTag = await headings[0].evaluate((el) => el.tagName.toLowerCase());
      expect(firstTag).toBe("h1");

      // Check there is exactly one h1
      const h1Count = await page.locator("h1").count();
      expect(h1Count).toBe(1);

      // Check heading levels don't skip (e.g., h1 -> h3 without h2)
      let prevLevel = 0;
      for (const heading of headings) {
        const tag = await heading.evaluate((el) => el.tagName.toLowerCase());
        const level = parseInt(tag.replace("h", ""), 10);
        // Allow same or lower level, or at most one level deeper
        if (prevLevel > 0) {
          expect(level).toBeLessThanOrEqual(prevLevel + 1);
        }
        prevLevel = level;
      }
    }
  });

  test("images have alt text", async ({ page }) => {
    await page.goto("/");

    const images = await page.locator("img").all();
    for (const img of images) {
      const alt = await img.getAttribute("alt");
      // alt attribute must exist (can be empty string for decorative images)
      expect(alt).not.toBeNull();
    }
  });

  test("page has lang attribute", async ({ page }) => {
    await page.goto("/");

    const lang = await page.locator("html").getAttribute("lang");
    expect(lang).toBeTruthy();
  });
});
