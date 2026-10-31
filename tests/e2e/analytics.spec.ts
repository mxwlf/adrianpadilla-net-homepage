import { test, expect } from "@playwright/test";

// The Google tag lives in the shared layout so that every page is measured.
// These checks assert the tags reach the rendered HTML; whether Google's
// endpoint answers is not something a build gate should depend on.
const MEASUREMENT_ID = "G-G7LFSQ4ZLB";
const SITE_URL = "https://adrianpadilla.net";
const PAGES = ["/", "/about/", "/about/me/", "/about/this-page/", "/404.html"];

test.describe("Analytics", () => {
  for (const path of PAGES) {
    test(`${path} loads the Google tag`, async ({ page }) => {
      await page.goto(path);

      const loader = page.locator(
        `head script[src="https://www.googletagmanager.com/gtag/js?id=${MEASUREMENT_ID}"]`
      );
      await expect(loader).toHaveCount(1);
      await expect(loader).toHaveAttribute("async", "");

      // Fingerprinted in real builds (analytics.<hash>.js), plain in dev.
      const bootstrap = page.locator(`head script[data-measurement-id="${MEASUREMENT_ID}"]`);
      await expect(bootstrap).toHaveCount(1);
      await expect(bootstrap).toHaveAttribute("src", /^\/assets\/js\/analytics(\.[a-f0-9]+)?\.js$/);
      await expect(bootstrap).toHaveAttribute("defer", "");
      await expect(bootstrap).toHaveAttribute("data-site-url", SITE_URL);
    });
  }

  // The flip side of the tags above: they ship everywhere, but the GA4
  // page_view comes from the `config` command, and this run is not real
  // traffic — it is localhost, driven by a webdriver. Withholding the command
  // is what keeps `make ci` out of the property. tests/unit/analytics.test.mjs
  // covers the production host, which a browser on localhost cannot reach.
  test("the bootstrap measures nothing outside production", async ({ page }) => {
    await page.goto("/");

    // dataLayer is what gtag.js drains when it loads. Its entries are
    // `arguments` objects, hence Array.from.
    const commands = await page.evaluate(() => {
      const queue: ArrayLike<unknown>[] | undefined = (
        window as unknown as { dataLayer?: ArrayLike<unknown>[] }
      ).dataLayer;
      return queue?.map((entry) => Array.from(entry).map(String));
    });

    // Defined, so gtag.js finds the queue it expects, but carrying no config.
    expect(commands).toBeDefined();
    expect(commands).not.toContainEqual(["config", MEASUREMENT_ID]);
  });

  // The site must work without JavaScript (project constitution): analytics is
  // additive, so a tag that never runs may not take the content with it.
  test("content still renders with JavaScript disabled", async ({ browser }) => {
    const context = await browser.newContext({ javaScriptEnabled: false });
    const page = await context.newPage();

    await page.goto("/");
    await expect(page.locator("main#content h1")).toBeVisible();

    await context.close();
  });
});
