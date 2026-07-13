const { test, expect } = require('@playwright/test');
const { createHash } = require('node:crypto');

const siteUrl = new URL(
  (process.env.SITE_URL || 'http://127.0.0.1:8765/').replace(/\/?$/, '/'),
);

test('傳家話影片由明確點擊解除靜音，開場音軌可聽且檔案可驗證', async ({ page }) => {
  const pageErrors = [];
  page.on('pageerror', (error) => pageErrors.push(String(error)));

  const videoPageUrl = new URL('deliverables/video/', siteUrl);
  await page.goto(videoPageUrl.href, { waitUntil: 'networkidle' });
  await expect(page).toHaveTitle(/傳家話/);
  await expect(page.getByRole('button', { name: '播放有聲預覽' })).toBeVisible();

  const verificationResponse = await page.request.get(
    new URL('verification.json', videoPageUrl).href,
  );
  expect(verificationResponse.ok()).toBeTruthy();
  const verification = await verificationResponse.json();
  const preview = verification.outputs.find((item) => item.role === 'web_preview_720p');
  expect(preview).toBeTruthy();

  const videoUrl = new URL('chuan-jia-hua-submission.mp4', videoPageUrl);
  const videoResponse = await page.request.get(videoUrl.href);
  expect(videoResponse.ok()).toBeTruthy();
  const videoBytes = await videoResponse.body();
  expect(videoBytes.length).toBe(preview.bytes);
  expect(createHash('sha256').update(videoBytes).digest('hex').toUpperCase())
    .toBe(preview.sha256);

  const video = page.locator('video');
  await expect(video.locator('source')).toHaveAttribute(
    'src',
    'chuan-jia-hua-submission.mp4',
  );
  expect(await video.evaluate((element) => ({
    controls: element.controls,
    muted: element.muted,
    volume: element.volume,
  }))).toEqual({ controls: true, muted: false, volume: 1 });

  await page.evaluate(() => {
    const element = document.querySelector('video');
    const button = document.getElementById('playWithSound');
    const context = new AudioContext();
    const analyser = context.createAnalyser();
    analyser.fftSize = 2048;
    const source = context.createMediaElementSource(element);
    source.connect(analyser);
    analyser.connect(context.destination);
    button.addEventListener('click', () => context.resume(), { once: true });
    window.__siteAudioAudit = { context, analyser };
  });

  await page.getByRole('button', { name: '播放有聲預覽' }).click();
  await expect.poll(() => video.evaluate((element) => ({
    paused: element.paused,
    muted: element.muted,
    volume: element.volume,
    currentTime: element.currentTime,
  }))).toMatchObject({ paused: false, muted: false, volume: 1 });
  await expect(page.locator('#soundStatus')).toContainText('有聲播放中');

  const openingEnergy = await page.evaluate(async () => {
    const { context, analyser } = window.__siteAudioAudit;
    await context.resume();
    const samples = new Float32Array(analyser.fftSize);
    let maximumRms = 0;
    const deadline = performance.now() + 5_000;
    while (performance.now() < deadline) {
      analyser.getFloatTimeDomainData(samples);
      let sumSquares = 0;
      for (const sample of samples) sumSquares += sample * sample;
      maximumRms = Math.max(maximumRms, Math.sqrt(sumSquares / samples.length));
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    return { maximumRms, state: context.state };
  });
  expect(openingEnergy.state).toBe('running');
  // 0.005 約為 -46 dBFS。低於此值的現行開場在一般筆電上近似無聲。
  expect(openingEnergy.maximumRms).toBeGreaterThan(0.005);
  expect(pageErrors).toEqual([]);
});

test('119 個 App 音檔 URL 可取用、PCM 非靜音，審閱控制項可由點擊播到 ended', async ({ page }) => {
  const manifestUrl = new URL(
    'deliverables/app/assets/assets/audio/piper_generation_manifest.json',
    siteUrl,
  );
  const manifestResponse = await page.request.get(manifestUrl.href);
  expect(manifestResponse.ok()).toBeTruthy();
  const manifest = await manifestResponse.json();
  expect(manifest.files).toHaveLength(119);

  const first = manifest.files[0];
  const firstAudioUrl = new URL(`deliverables/app/assets/${first.path}`, siteUrl);
  const audioResponse = await page.request.get(firstAudioUrl.href);
  expect(audioResponse.ok()).toBeTruthy();
  const audioBytes = await audioResponse.body();
  expect(audioBytes.length).toBe(first.bytes);
  expect(createHash('sha256').update(audioBytes).digest('hex').toUpperCase())
    .toBe(first.sha256);

  await page.goto(new URL('deliverables/review/', siteUrl).href, {
    waitUntil: 'networkidle',
  });
  const decodedEnergy = await page.evaluate(async (url) => {
    const response = await fetch(url, { cache: 'no-store' });
    const bytes = await response.arrayBuffer();
    const context = new AudioContext();
    try {
      const buffer = await context.decodeAudioData(bytes);
      let sumSquares = 0;
      let sampleCount = 0;
      let maximum = 0;
      for (let channel = 0; channel < buffer.numberOfChannels; channel += 1) {
        const data = buffer.getChannelData(channel);
        for (const sample of data) {
          sumSquares += sample * sample;
          sampleCount += 1;
          maximum = Math.max(maximum, Math.abs(sample));
        }
      }
      return {
        duration: buffer.duration,
        rms: Math.sqrt(sumSquares / sampleCount),
        maximum,
      };
    } finally {
      await context.close();
    }
  }, firstAudioUrl.href);
  expect(decodedEnergy.duration).toBeGreaterThan(0);
  expect(decodedEnergy.rms).toBeGreaterThan(0.01);
  expect(decodedEnergy.maximum).toBeGreaterThan(0.05);

  const cards = page.locator('.review-card');
  await expect(cards).toHaveCount(119);
  const audio = cards.first().locator('audio');
  expect(await audio.evaluate((element) => ({
    muted: element.muted,
    volume: element.volume,
    controls: element.controls,
  }))).toEqual({ muted: false, volume: 1, controls: true });

  await audio.click({ position: { x: 22, y: 24 } });
  await expect(cards.first().locator('[data-playback-state]'))
    .toContainText('已完整播放 1 次', { timeout: 15_000 });
});
