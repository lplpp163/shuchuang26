const { defineConfig } = require('@playwright/test');

const browserChannel = process.env.PLAYWRIGHT_CHANNEL;

module.exports = defineConfig({
  testDir: __dirname,
  testMatch: /.*(?:web_smoke|visual_audit|native_review|deliverables_media|pilot_workbench)\.spec\.js/,
  timeout: 90_000,
  expect: {
    // Flutter's first CanvasKit/semantics boot can be slower on a cold CI worker.
    // Assertions still wait on observable UI state; this is only the safety cap.
    timeout: 20_000,
  },
  use: {
    browserName: 'chromium',
    ...(browserChannel ? { channel: browserChannel } : {}),
    headless: true,
    actionTimeout: 20_000,
    navigationTimeout: 30_000,
    trace: 'retain-on-failure',
  },
});
