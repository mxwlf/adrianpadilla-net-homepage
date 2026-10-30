import { test, expect } from "@playwright/test";

// The Google tag lives in the shared layout so that every page is measured.
// These checks assert the tags reach the rendered HTML; whether Google's
// endpoint answers is not something a build gate should depend on.
const MEASUREMENT_ID = "G-G7LFSQ4ZLB";
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
    });
  }

  test("the bootstrap queues the config command for gtag.js", async ({ page }) => {
    await page.goto("/");

    // dataLayer is what gtag.js drains when it loads, so a queued `config`
    // command for this property is the real contract of the bootstrap. Its
    // entries are `arguments` objects, hence Array.from.
    const commands = await page.evaluate(() => {
      const queue: ArrayLike<unknown>[] =
        (window as unknown as { dataLayer?: ArrayLike<unknown>[] }).dataLayer ?? [];
      return queue.map((entry) => Array.from(entry).map(String));
    });

    expect(commands).toContainEqual(["config", MEASUREMENT_ID]);
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
