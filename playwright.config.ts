import {defineConfig, devices} from '@playwright/test';

const baseURL = process.env.E2E_BASE_URL ?? 'http://127.0.0.1:4173';

export default defineConfig({
  testDir: './e2e',
  timeout: 60_000,
  fullyParallel: false,
  workers: 1,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [['line'], ['html', {open: 'never'}]] : 'line',
  use: {
    ...devices['Desktop Chrome'],
    baseURL,
    screenshot: 'only-on-failure',
    trace: 'on-first-retry',
    video: 'retain-on-failure',
  },
  webServer: {
    command: 'node scripts/e2e/spa_server.mjs build/web_erp',
    url: `${baseURL}/login`,
    reuseExistingServer: !process.env.CI,
    timeout: 30_000,
  },
});
