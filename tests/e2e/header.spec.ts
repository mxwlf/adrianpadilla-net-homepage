import { test, expect } from "@playwright/test";

test.describe("About submenu", () => {
  test("opens on hover and navigates", async ({ page }) => {
    await page.goto("/");

    const me = page.locator('.submenu a[href="/about/me/"]');
    await expect(me).toBeHidden();

    await page.hover(".submenu-trigger");
    await expect(me).toBeVisible();

    await me.click();
    await expect(page).toHaveURL(/\/about\/me\/$/);
  });

  test("opens when the trigger takes keyboard focus", async ({ page }) => {
    await page.goto("/");

    const trigger = page.locator(".submenu-trigger");
    const me = page.locator('.submenu a[href="/about/me/"]');

    await trigger.focus();
    await expect(me).toBeVisible();

    // The submenu is the next thing in the tab order, so a keyboard user
    // reaches it without needing a script to expand anything.
    await page.keyboard.press("Tab");
    await expect(me).toBeFocused();
  });

  test("submenu still works with JavaScript disabled", async ({ browser }) => {
    const context = await browser.newContext({
      javaScriptEnabled: false,
      // The panel slides in over 0.3s. Playwright cannot run the animation
      // frames it uses to confirm a target has stopped moving while script
      // execution is off, so it would never agree the link is clickable.
      // Reduced motion collapses the transition, which this stylesheet
      // honours — so the panel is simply there, and the click lands.
      reducedMotion: "reduce",
    });
    const page = await context.newPage();
    await page.goto("/");

    const thisPage = page.locator('.submenu a[href="/about/this-page/"]');
    await page.hover(".submenu-trigger");
    await expect(thisPage).toBeVisible();
    await thisPage.click();
    await expect(page).toHaveURL(/\/about\/this-page\/$/);

    await context.close();
  });
});

test.describe("Theme toggle", () => {
  test("flips the theme and remembers the choice", async ({ page }) => {
    await page.goto("/");

    const toggle = page.locator("#theme-toggle");
    await expect(toggle).toBeVisible();

    const before = await toggle.getAttribute("aria-pressed");
    await toggle.click();
    const after = await toggle.getAttribute("aria-pressed");
    expect(after).not.toBe(before);

    const chosen = await page.evaluate(() => document.documentElement.dataset.theme);
    expect(chosen).toBe(after === "true" ? "dark" : "light");

    // The choice has to survive a page load, not just a click.
    await page.goto("/about/");
    await expect(page.locator("html")).toHaveAttribute("data-theme", chosen!);
    await expect(page.locator("#theme-toggle")).toHaveAttribute("aria-pressed", after!);
  });

  test("follows the OS preference until overridden", async ({ page }) => {
    await page.emulateMedia({ colorScheme: "dark" });
    await page.goto("/");

    await expect(page.locator("html")).not.toHaveAttribute("data-theme", /.+/);
    await expect(page.locator("#theme-toggle")).toHaveAttribute("aria-pressed", "true");
    await expect(page.locator("body")).toHaveCSS("background-color", "rgb(51, 51, 51)");
  });

  test("theme follows the OS and the control hides without JavaScript", async ({ browser }) => {
    const context = await browser.newContext({
      javaScriptEnabled: false,
      colorScheme: "dark",
    });
    const page = await context.newPage();
    await page.goto("/");

    // CSS alone must deliver the dark theme; the button is the only part that
    // needs a script, so it stays hidden rather than sitting there inert.
    await expect(page.locator("body")).toHaveCSS("background-color", "rgb(51, 51, 51)");
    await expect(page.locator("#theme-toggle")).toBeHidden();

    await context.close();
  });
});
