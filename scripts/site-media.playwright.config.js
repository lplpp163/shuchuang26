const { defineConfig } = require('@playwright/test');

module.exports = defineConfig({
  testDir: __dirname,
  testMatch: /site-media\.spec\.js/,
  timeout: 90_000,
  expect: { timeout: 20_000 },
  use: {
    browserName: 'chromium',
    ...(process.env.PLAYWRIGHT_CHANNEL
      ? { channel: process.env.PLAYWRIGHT_CHANNEL }
      : {}),
    headless: true,
    actionTimeout: 20_000,
    navigationTimeout: 30_000,
    trace: 'retain-on-failure',
  },
});
