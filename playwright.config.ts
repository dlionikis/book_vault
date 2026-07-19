import { defineConfig, devices } from '@playwright/test';

/**
 * Playwright config for the Book Vault web smoke (Phase 6).
 *
 * - testDir `e2e` sits outside every Jest `testMatch`, so it never collides with
 *   the three-project unit/integration/contract split.
 * - `globalSetup` probes Docker Postgres (port 5433) and seeds deterministic
 *   fixtures BEFORE any test or the dev server starts.
 * - `webServer` lets Playwright own the dev server lifecycle locally (start +
 *   wait-for-ready + shutdown). `reuseExistingServer` means a dev server you
 *   already have running is reused instead of spawning a second one.
 *
 * Docker is NOT managed here by design: if Postgres isn't up, globalSetup fails
 * with a clear "run docker-compose up -d" message rather than starting it.
 */

const PORT = Number(process.env.E2E_PORT || 3000);
const BASE_URL = process.env.E2E_BASE_URL || `http://localhost:${PORT}`;

export default defineConfig({
  testDir: './e2e',
  globalSetup: './e2e/global-setup.ts',
  // Smoke is deliberately serial and small; parallelism buys nothing and risks
  // cross-test data races on the single seeded fixture.
  fullyParallel: false,
  workers: 1,
  forbidOnly: !!process.env.CI,
  // One retry: absorbs the occasional cold-start/timing blip without masking a
  // genuinely broken run (a real failure fails twice).
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [['github'], ['list']] : 'list',
  timeout: 60_000,
  // 15s (not the 10s default): against a cold Next 16 + Turbopack dev server,
  // the first hit to each route compiles on demand, and client-hydration-gated
  // assertions (e.g. the AddToLibrary button flipping to "In Library" after
  // useSession hydrates) can exceed 10s on that first compile. The add itself
  // returns 201 well within budget — this is dev-server warmup latency, not app
  // slowness. Prod is prebuilt, so this only affects the E2E dev server.
  expect: { timeout: 15_000 },

  use: {
    baseURL: BASE_URL,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },

  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],

  webServer: {
    command: 'npm run dev',
    url: `${BASE_URL}/api/health`,
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
    stdout: 'pipe',
    stderr: 'pipe',
  },
});
