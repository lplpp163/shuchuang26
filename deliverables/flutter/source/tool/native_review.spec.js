const { test, expect } = require('@playwright/test');
const { createHash } = require('node:crypto');

const reviewUrl = process.env.REVIEW_URL
  || 'http://127.0.0.1:8765/deliverables/review/';
const portableReviewUrl = process.env.PORTABLE_REVIEW_URL || '';

async function verifyAllClips(page, url, expectedSrc) {
  await page.goto(url, { waitUntil: 'networkidle' });
  const cards = page.locator('.review-card');
  await expect(cards).toHaveCount(119);

  const clips = await cards.evaluateAll((elements) => elements.map((card) => ({
    path: card.dataset.path,
    bytes: Number(card.dataset.bytes),
    sha256: card.dataset.sha256,
    src: card.querySelector('audio').getAttribute('src'),
  })));
  expect(new Set(clips.map((item) => item.path)).size).toBe(119);
  expect(new Set(clips.map((item) => item.src)).size).toBe(119);

  // Keep verification pressure below the local demo server's accept backlog.
  // Every clip is still fetched and hashed; only the concurrency is bounded.
  const requestBatchSize = 4;
  for (let offset = 0; offset < clips.length; offset += requestBatchSize) {
    await Promise.all(clips.slice(offset, offset + requestBatchSize).map(async (item) => {
      expect(item.path).toMatch(/^assets\/audio\/[A-Za-z0-9._-]+\.mp3$/);
      expect(item.src).toMatch(expectedSrc);
      expect(item.bytes).toBeGreaterThan(0);
      expect(item.sha256).toMatch(/^[A-F0-9]{64}$/);
      const response = await page.request.get(new URL(item.src, url).href);
      expect(response.ok(), item.path).toBeTruthy();
      const body = await response.body();
      expect(body.length, item.path).toBe(item.bytes);
      expect(createHash('sha256').update(body).digest('hex').toUpperCase(), item.path)
        .toBe(item.sha256);
    }));
  }
  return cards;
}

async function playThrough(card) {
  return card.locator('audio').evaluate((audio) => new Promise((resolve, reject) => {
    const events = [];
    const timeout = setTimeout(() => reject(new Error('Timed out waiting for audio ended')), 15_000);
    for (const name of ['play', 'playing', 'ended', 'error']) {
      audio.addEventListener(name, () => {
        events.push(name);
        if (name === 'error') {
          clearTimeout(timeout);
          reject(new Error('Audio element emitted error'));
        }
        if (name === 'ended') {
          clearTimeout(timeout);
          resolve(events);
        }
      });
    }
    audio.muted = true;
    audio.play().catch((error) => {
      clearTimeout(timeout);
      reject(error);
    });
  }));
}

test('native-review packet verifies 119 clips, tri-state rules, ended playback and v2 evidence', async ({ page }) => {
  const pageErrors = [];
  page.on('pageerror', (error) => pageErrors.push(String(error)));

  await page.goto(reviewUrl, { waitUntil: 'networkidle' });
  await page.evaluate(() => localStorage.clear());
  const cards = await verifyAllClips(
    page,
    reviewUrl,
    /^\.\.\/app\/assets\/assets\/audio\/.+\.mp3$/,
  );

  await expect(page.getByText(/已聽完 0／119 · 已判定 0／119/)).toBeVisible();
  await expect(page.getByText('這是一份空白真人審閱工具，不是審閱成果')).toBeVisible();

  const firstCard = cards.first();
  await expect(firstCard.locator('input[type="radio"]:checked')).toHaveCount(0);
  await expect(firstCard.locator('[data-set-status="pass"]')).toBeDisabled();
  await expect(firstCard.locator('[data-set-status="revise"]')).toBeDisabled();

  const firstPlaybackEvents = await playThrough(firstCard);
  expect(firstPlaybackEvents).toContain('play');
  expect(firstPlaybackEvents).toContain('playing');
  expect(firstPlaybackEvents.at(-1)).toBe('ended');
  await expect(firstCard.locator('[data-playback-state]')).toContainText('已完整播放 1 次');
  await expect(firstCard.locator('[data-set-status="pass"]')).toBeDisabled();

  await firstCard.locator('[data-key="textNatural"][value="yes"]').check();
  await firstCard.locator('[data-key="familyRegister"][value="yes"]').check();
  await firstCard.locator('[data-key="audioClear"][value="yes"]').check();
  await firstCard.locator('[data-key="rating"]').selectOption('4');
  await expect(firstCard.locator('[data-set-status="pass"]')).toBeEnabled();
  await expect(firstCard.locator('[data-set-status="revise"]')).toBeDisabled();
  await firstCard.locator('[data-set-status="pass"]').click();

  const secondCard = cards.nth(1);
  const secondPlaybackEvents = await playThrough(secondCard);
  expect(secondPlaybackEvents.at(-1)).toBe('ended');
  await secondCard.locator('[data-key="textNatural"][value="no"]').check();
  await secondCard.locator('[data-key="familyRegister"][value="yes"]').check();
  await secondCard.locator('[data-key="audioClear"][value="yes"]').check();
  await secondCard.locator('[data-key="rating"]').selectOption('2');
  await expect(secondCard.locator('[data-set-status="pass"]')).toBeDisabled();
  await expect(secondCard.locator('[data-set-status="revise"]')).toBeDisabled();
  await secondCard.locator('[data-key="correction"]').fill('請由母語審閱者填寫實際修訂');
  await expect(secondCard.locator('[data-set-status="revise"]')).toBeEnabled();
  await secondCard.locator('[data-set-status="revise"]').click();

  const today = new Date().toISOString().slice(0, 10);
  await page.locator('#reviewerCode').fill('R01');
  await page.locator('#reviewDate').fill(today);
  await page.locator('#languageContext').fill('南部家庭用語');
  await page.locator('#childExperience').selectOption('偶爾');
  await page.locator('#nativeSpeakerAttestation').check();
  await page.locator('#anonymousUseConsent').check();
  await expect(page.getByText(/已聽完 2／119 · 已判定 2／119 · 需修訂 1/)).toBeVisible();

  await page.reload({ waitUntil: 'networkidle' });
  await expect(page.locator('.review-card').first().locator('[data-set-status="pass"]'))
    .toHaveAttribute('aria-pressed', 'true');
  await expect(page.locator('.review-card').nth(1).locator('[data-set-status="revise"]'))
    .toHaveAttribute('aria-pressed', 'true');
  await expect(page.locator('.review-card').first().locator('[data-key="rating"]')).toHaveValue('4');

  const downloadPromise = page.waitForEvent('download');
  await page.locator('#exportJson').click();
  const download = await downloadPromise;
  const stream = await download.createReadStream();
  const chunks = [];
  for await (const chunk of stream) chunks.push(chunk);
  const evidence = JSON.parse(Buffer.concat(chunks).toString('utf8'));

  expect(evidence.schema).toBe('our-family-says/native-review/v2');
  expect(evidence.manifestSha256).toMatch(/^[A-F0-9]{64}$/);
  expect(evidence.contextCatalogSha256).toMatch(/^[A-F0-9]{64}$/);
  expect(Object.keys(evidence.contextSourceSha256).sort()).toEqual([
    'lib/models/conversation_episode.dart',
    'lib/services/app_store.dart',
  ]);
  expect(evidence.reviews).toHaveLength(119);
  expect(evidence.meta.nativeSpeakerAttestation).toBe(true);
  expect(evidence.meta.anonymousUseConsent).toBe(true);
  expect(evidence.completion).toEqual({
    metadataComplete: true,
    playedCount: 2,
    judgedCount: 2,
    complete: false,
  });
  expect(evidence.reviews[0]).toMatchObject({
    status: 'pass', played: true, playCount: 1,
    textNatural: 'yes', familyRegister: 'yes', audioClear: 'yes', rating: '4',
  });
  expect(evidence.reviews[0].lastPlayedAt).toMatch(/^20\d\d-/);
  expect(evidence.reviews[0].lastDurationSeconds).toBeGreaterThan(0);
  expect(evidence.reviews[0].contexts.length).toBeGreaterThan(0);
  expect(evidence.reviews[1]).toMatchObject({
    status: 'revise', played: true, textNatural: 'no', familyRegister: 'yes',
    audioClear: 'yes', rating: '2',
  });
  expect(evidence.reviews.some((review) => review.registerReviewScope.startsWith('explicit-markers-only')))
    .toBe(true);

  await page.evaluate(() => localStorage.clear());
  expect(pageErrors).toEqual([]);
});

test('portable ZIP layout serves the same 119 verified clips', async ({ page }) => {
  test.skip(!portableReviewUrl, 'Set PORTABLE_REVIEW_URL after extracting the generated ZIP.');
  const pageErrors = [];
  page.on('pageerror', (error) => pageErrors.push(String(error)));
  await verifyAllClips(page, portableReviewUrl, /^\.\/assets\/audio\/.+\.mp3$/);
  expect(await playThrough(page.locator('.review-card').first())).toContain('ended');
  await expect(page.locator('.review-card').first().locator('[data-playback-state]'))
    .toContainText('已完整播放 1 次');
  expect(pageErrors).toEqual([]);
});
