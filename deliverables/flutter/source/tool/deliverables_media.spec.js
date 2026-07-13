const { test, expect } = require('@playwright/test');
const { createHash } = require('node:crypto');

const siteUrl = (process.env.SITE_URL || 'http://127.0.0.1:8765/').replace(/\/?$/, '/');

test('video page serves the verified sub-25MiB preview and decodes when H.264 is available', async ({ page }) => {
  const pageErrors = [];
  page.on('pageerror', (error) => pageErrors.push(String(error)));

  await page.goto(new URL('deliverables/video/', siteUrl).href, { waitUntil: 'networkidle' });
  await expect(page.getByText('正式初審影片網頁預覽｜02:53.9')).toBeVisible();

  const verificationResponse = await page.request.get(
    new URL('deliverables/video/verification.json', siteUrl).href,
  );
  expect(verificationResponse.ok()).toBeTruthy();
  const verification = await verificationResponse.json();
  expect(verification.schemaVersion).toBe(3);
  expect(verification.validation).toBe('PASS');
  const preview = verification.outputs.find((item) => item.role === 'web_preview_720p');
  const formal = verification.outputs.find((item) => item.role === 'submission_1080p');
  expect(preview).toBeTruthy();
  expect(formal).toBeTruthy();
  expect(preview.bytes).toBeLessThan(25 * 1024 * 1024);
  expect(preview.video).toMatchObject({ codec: 'h264', width: 1280, height: 720 });
  expect(preview.audio).toMatchObject({ codec: 'aac', sampleRate: 48000, channels: 2 });
  expect(formal.video).toMatchObject({ codec: 'h264', width: 1920, height: 1080 });

  const mediaResponse = await page.request.get(
    new URL('deliverables/video/chuan-jia-hua-submission.mp4', siteUrl).href,
  );
  expect(mediaResponse.ok()).toBeTruthy();
  const body = await mediaResponse.body();
  expect(body.length).toBe(preview.bytes);
  expect(createHash('sha256').update(body).digest('hex').toUpperCase()).toBe(preview.sha256);

  const mediaEvidence = await page.locator('video').evaluate((video) => new Promise((resolve, reject) => {
    const codecSupport = video.canPlayType('video/mp4; codecs="avc1.640028, mp4a.40.2"');
    if (!codecSupport) {
      resolve({ supported: false, codecSupport });
      return;
    }
    const observed = [];
    for (const name of ['loadedmetadata', 'play', 'playing', 'waiting', 'ended']) {
      video.addEventListener(name, () => observed.push(name));
    }
    const timeout = setTimeout(() => reject(new Error(`Timed out decoding the Web preview: ${JSON.stringify({
      currentTime: video.currentTime,
      duration: video.duration,
      readyState: video.readyState,
      networkState: video.networkState,
      seeking: video.seeking,
      observed,
    })}`)), 45_000);
    const finish = (value) => {
      clearTimeout(timeout);
      resolve(value);
    };
    const fail = () => {
      clearTimeout(timeout);
      reject(new Error(`Video element failed with code ${video.error?.code || 'unknown'}`));
    };
    video.addEventListener('error', fail, { once: true });
    const seekAndPlay = () => {
      const dimensions = {
        width: video.videoWidth,
        height: video.videoHeight,
        duration: video.duration,
      };
      video.muted = true;
      video.playbackRate = 16;
      const events = [];
      for (const name of ['play', 'playing', 'ended']) {
        video.addEventListener(name, () => {
          events.push(name);
          if (name === 'ended') finish({ supported: true, codecSupport, ...dimensions, events });
        }, { once: true });
      }
      video.play().catch(reject);
    };
    if (video.readyState >= HTMLMediaElement.HAVE_METADATA) {
      seekAndPlay();
    } else {
      video.addEventListener('loadedmetadata', seekAndPlay, { once: true });
      video.load();
    }
  }));
  if (mediaEvidence.supported) {
    expect(mediaEvidence.width).toBe(1280);
    expect(mediaEvidence.height).toBe(720);
    expect(mediaEvidence.duration).toBeGreaterThan(173);
    expect(mediaEvidence.duration).toBeLessThan(180);
    expect(mediaEvidence.events).toEqual(['play', 'playing', 'ended']);
  } else {
    expect(mediaEvidence.codecSupport).toBe('');
  }
  expect(pageErrors).toEqual([]);
});
