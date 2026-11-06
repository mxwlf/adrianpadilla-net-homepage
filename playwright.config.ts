import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "tests/e2e",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: "line",
  use: {
    baseURL: "http://localhost:4173",
    trace: "on-first-retry",
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],
  webServer: {
    // `serve` is a devDependency rather than an ad-hoc `npx serve`, for the
    // reason release.yml gives for the SWA CLI: a project dependency is tracked
    // by Dependabot and seen by osv-scan, while a download at test time is
    // neither. `--no` says "never fetch it" -- but it is the dependency that
    // makes that hold, because npx will quietly run a copy from its own cache.
    command: "npm exec --no -- serve dist -l 4173",
    port: 4173,
    reuseExistingServer: !process.env.CI,
  },
});
