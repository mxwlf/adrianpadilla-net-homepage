import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "tests/a11y",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: "line",
  use: {
    baseURL: "http://localhost:4174",
    trace: "on-first-retry",
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],
  webServer: {
    // See the note in playwright.config.ts: `serve` is a pinned devDependency,
    // never a download at test time.
    command: "npm exec --no -- serve dist -l 4174",
    port: 4174,
    reuseExistingServer: !process.env.CI,
  },
});
