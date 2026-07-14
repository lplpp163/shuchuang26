const { test, expect } = require('@playwright/test');

const baseURL = process.env.HOMETONGUE_URL || 'http://127.0.0.1:8766/';

async function afterPaint(page) {
  await page.evaluate(() => new Promise((resolve) => {
    requestAnimationFrame(() => requestAnimationFrame(resolve));
  }));
}

async function typeFlutterText(page, locator, value) {
  await locator.click();
  await page.keyboard.press('Control+A');
  await page.keyboard.press('Backspace');
  await locator.pressSequentially(value, { delay: 35 });
  if (await locator.inputValue() !== value) {
    await locator.fill(value);
  }
  await expect(locator).toHaveValue(value);
  await page.keyboard.press('Tab');
  await afterPaint(page);
}

async function waitForDecodedImages(page) {
  const broken = await page.evaluate(async () => {
    if (document.fonts?.ready) await document.fonts.ready;
    const images = [...document.images];
    await Promise.all(images.map(async (image) => {
      if (!image.complete) {
        await new Promise((resolve) => {
          image.addEventListener('load', resolve, { once: true });
          image.addEventListener('error', resolve, { once: true });
        });
      }
      if (typeof image.decode === 'function' && image.naturalWidth > 0) {
        await image.decode().catch(() => {});
      }
    }));
    return images
      .filter((image) => image.complete && image.naturalWidth === 0)
      .map((image) => image.currentSrc || image.src);
  });
  expect(broken, `broken image elements: ${broken.join(', ')}`).toEqual([]);
  await afterPaint(page);
}

async function captureReady(page, anchor, path, errors) {
  await expect(anchor).toBeVisible();
  await waitForDecodedImages(page);
  expect(errors, `page errors before ${path}`).toEqual([]);
  await page.screenshot({ path, animations: 'disabled' });
}

async function openColdApp(page, errors) {
  await page.addInitScript(() => {
    window.SpeechSynthesisUtterance = class HometongueTestUtterance {
      constructor(text = '') {
        this.text = text;
        this.lang = '';
        this.pitch = 1;
        this.rate = 1;
        this.volume = 1;
        this.voice = null;
      }
    };
    const synth = window.speechSynthesis;
    if (!synth || synth.__hometongueTestDriver) return;
    synth.__hometongueTestDriver = true;
    const vietnameseVoice = {
      default: true,
      lang: 'vi-VN',
      localService: true,
      name: 'Hometongue Vietnamese Test Voice',
      voiceURI: 'hometongue-test-vi-VN',
    };
    synth.getVoices = () => [vietnameseVoice];
    synth.speak = (utterance) => {
      setTimeout(() => utterance.onstart?.(new Event('start')), 0);
      setTimeout(() => utterance.onend?.(new Event('end')), 80);
    };
    synth.cancel = () => {};
    synth.pause = () => {};
    synth.resume = () => {};
  });
  await page.goto(baseURL, { waitUntil: 'domcontentloaded' });
  const accessibility = page.getByRole('button', { name: 'Enable accessibility' });
  const consent = page.getByText('先取得家人的同意');
  await expect.poll(async () =>
    (await accessibility.count()) + (await consent.count()))
    .toBeGreaterThan(0);
  if (await accessibility.count()) {
    await accessibility
      .evaluate((element) => element.click(), { timeout: 2_000 })
      .catch(() => {});
  }
  await captureReady(
    page,
    consent,
    'test-results/cold-start-consent-pixel7.png',
    errors,
  );
}

async function establishFamilyCircle(page, errors) {
  const recordingConsent = page.getByRole('checkbox', {
    name: /我已得到錄音者與孩子監護人的同意/,
  });
  await recordingConsent.click();
  await expect(recordingConsent).toBeChecked();
  const localDataConsent = page.getByRole('checkbox', {
    name: /我了解資料會保存在這支裝置/,
  });
  await localDataConsent.click();
  await expect(localDataConsent).toBeChecked();
  await typeFlutterText(
    page,
    page.getByRole('textbox', { name: '設定四位數家長碼' }),
    '2468',
  );
  const acceptButton = page.getByRole('button', { name: '同意並開始' });
  await expect(acceptButton).toBeEnabled();
  await acceptButton.click();

  const setupTitle = page.getByText('先建立你們家的小圈圈');
  await captureReady(
    page,
    setupTitle,
    'test-results/family-circle-setup-pixel7.png',
    errors,
  );
  const elderName = page.getByRole('textbox', { name: '孩子怎麼叫這位長輩？' });
  await typeFlutterText(page, elderName, '阿嬤');
  const childName = page.getByRole('textbox', { name: '孩子的小名' });
  await typeFlutterText(page, childName, '小米');
  await page.getByRole('checkbox', {
    name: /我是成人，確認以上兩位可以加入這個家庭圈/,
  }).click({ force: true });
  const createCircle = page.getByRole('button', { name: '確認家人，進入故事劇場' });
  await expect(createCircle).toBeEnabled();
  await createCircle.click();
  await expect(page.getByText('今天，阿嬤在等你接故事')).toBeVisible();
  await waitForDecodedImages(page);
}

async function scrollUntilAttached(page, locator, deltaY = 430) {
  for (let index = 0; index < 18 && !(await locator.count()); index += 1) {
    await page.mouse.wheel(0, deltaY);
    await afterPaint(page);
  }
  await expect(locator).toBeAttached();
  await locator.scrollIntoViewIfNeeded();
  await afterPaint(page);
}

async function chooseByCard(page, translation) {
  const prepare = page.getByRole('button', {
    name: `圖像選擇「${translation}」；選取後可以開口或直接繼續故事`,
  });
  await scrollUntilAttached(page, prepare);
  await prepare.click();
  const choice = page.getByRole('button', {
    name: /不開麥克風，用這張圖讓.+回話/,
  });
  await scrollUntilAttached(page, choice);
  await choice.click();
  const next = page.getByRole('button', {
    name: /看接下來發生什麼|完成這一集|馬上接下去|馬上收好故事|我看完了，接著演/,
  });
  await scrollUntilAttached(page, next);
  await expect(next).toBeEnabled({ timeout: 20_000 });
  return next;
}

async function unlockParent(page, errors) {
  await page.getByRole('button', { name: '交給家人', exact: true }).click();
  await captureReady(
    page,
    page.getByText('接下來請把裝置交給家人'),
    'test-results/family-handoff-pixel7.png',
    errors,
  );
  await page.getByRole('button', { name: '家庭管理者・出題與管理' }).click();
  await page.getByRole('textbox', { name: '四位數家長碼' }).fill('2468');
  await page.getByRole('button', { name: '確認' }).click();
  await expect(page.getByText('家人怎麼參與？')).toBeVisible();
}

const clubRelayTarget = 'Hôm nay con tham gia câu lạc bộ lần đầu';

async function completeClubFamilyRelayVisual(page, errors) {
  await page.getByRole('tab', { name: '選故事' }).click();
  await page.getByRole('button', { name: '社團' }).click();
  await expect(page.getByText('小米的第一棒')).toBeVisible();
  await page.getByRole('button', {
    name: '我今天第一次參加社團',
  }).click();
  await captureReady(
    page,
    page.getByText('把「社團」交給家人'),
    'test-results/family-relay-handoff-pixel7.png',
    errors,
  );
  await page.getByRole('button', { name: '已交給家人' }).click();
  await page.getByRole('textbox', { name: '四位數家長碼' }).fill('2468');
  await page.getByRole('button', { name: '確認' }).click();

  await expect(page.getByRole('group', {
    name: /把「社團」變成四關故事任務/,
  })).toBeVisible();
  const generate = page.getByRole('button', { name: '產生本機故事草稿' });
  await scrollUntilAttached(page, generate);
  await generate.click();
  await expect(page.getByRole('group', {
    name: /孩子收到的不是一張答案卡，是四關生活任務/,
  })).toBeVisible();
  const target = page.getByRole('textbox', {
    name: /孩子要說（請用\s*越南語）/,
  });
  await scrollUntilAttached(page, target);
  await typeFlutterText(page, target, clubRelayTarget);
  const advanced = page.getByRole('button', { name: /想再調整題目/ });
  await scrollUntilAttached(page, advanced);
  await advanced.click();
  await typeFlutterText(
    page,
    page.getByRole('textbox', { name: '句子積木' }),
    'Hôm nay | con tham gia | câu lạc bộ lần đầu',
  );
  const familyConfirmed = page.getByRole('checkbox', {
    name: /我確認這是我們家會說的方式/,
  });
  await scrollUntilAttached(page, familyConfirmed);
  await familyConfirmed.click();
  const save = page.getByRole('button', { name: '建立並交給孩子闖四關' });
  await scrollUntilAttached(page, save);
  await save.click();

  await expect(page.getByText('回到家的時刻')).toBeVisible();
  await page.getByRole('button', { name: '回家的孩子', exact: true }).click();
  await page.getByRole('button', { name: '下一關' }).click();
  const listen = page.getByRole('button', { name: /點一下聽/ });
  await scrollUntilAttached(page, listen);
  await listen.click();
  await expect(page.getByRole('button', { name: /再聽一次/ }))
    .toBeVisible();
  await page.getByRole('button', { name: '回家的孩子', exact: true }).click();
  await page.getByRole('button', { name: '下一關' }).click();

  for (const token of [
    'Hôm',
    'nay',
    'con',
    'tham',
    'gia',
    'câu',
    'lạc',
    'bộ',
    'lần',
    'đầu',
  ]) {
    // Flutter's Edge semantics tree can prefix nearby Chinese labels to the
    // first token (for example, "次參加社團ôm"). Match the token at the end of
    // the button name so the audit still clicks the actual word control.
    const tokenName = token === 'Hôm' ? /(?:H)?ôm$/u : new RegExp(`${token}$`, 'u');
    const word = page.getByRole('button', { name: tokenName }).last();
    await scrollUntilAttached(page, word, -430);
    await word.click();
  }
  await expect(page.getByText(/句子排好了/)).toBeVisible();
  await page.getByRole('button', { name: '下一關' }).click();
  const relayAnswer = page.getByRole('button', {
    name: new RegExp(clubRelayTarget),
  });
  await scrollUntilAttached(page, relayAnswer);
  await relayAnswer.click();
  await page.getByRole('button', { name: '看我的星星' }).click();
  await page.getByRole('button', { name: '收下星星，跟著說' }).click();

  const hearFamilyVersion = page.getByRole('button', { name: '聽裝置示範音' });
  await scrollUntilAttached(page, hearFamilyVersion);
  await hearFamilyVersion.click();
  await expect(page.getByRole('button', { name: '再聽裝置示範音' }))
    .toBeVisible();
  const textFallback = page.getByRole('button', { name: /麥克風不能用/ });
  await scrollUntilAttached(page, textFallback);
  await textFallback.click();
  await typeFlutterText(
    page,
    page.getByRole('textbox', { name: '寫下自己想說的話' }),
    clubRelayTarget,
  );
  const finishChildBaton = page.getByRole('button', { name: '存到這台裝置' });
  await scrollUntilAttached(page, finishChildBaton);
  await finishChildBaton.click();

  await captureReady(
    page,
    page.getByText('三棒接成一個家的故事'),
    'test-results/family-relay-reveal-pixel7.png',
    errors,
  );
  const playRelay = page.getByRole('button', { name: '一起播放我們的接力' });
  await scrollUntilAttached(page, playRelay);
  await playRelay.click();
  await expect(page.getByRole('button', { name: '一起播放我們的接力' }))
    .toBeVisible();
  await page.getByRole('button', { name: '收進家人圈' }).click();

  await page.getByRole('tab', { name: '家人圈' }).click();
  const relayCircleCard = page.getByText('三棒家庭接力');
  await scrollUntilAttached(page, relayCircleCard);
  await captureReady(
    page,
    relayCircleCard,
    'test-results/family-relay-in-circle-pixel7.png',
    errors,
  );
  await expect(page.getByText(
    /家庭接力・社團[\s\S]*我今天第一次參加社團。[\s\S]*Hôm nay con tham gia câu lạc bộ lần đầu[\s\S]*用文字完成這一棒/,
  )).toBeVisible();
}

test('Pixel 7 cold-start, beginner theater, story card, and family-response audit', async ({ page }) => {
  await page.setViewportSize({ width: 412, height: 915 });
  const errors = [];
  page.on('pageerror', (error) =>
    errors.push(error.stack || `${error.name}: ${error.message}`));

  await openColdApp(page, errors);
  await page.getByRole('button', { name: '先試演約 30 秒' }).click();
  await captureReady(
    page,
    page.getByRole('button', { name: '點一下聽外婆開場' }),
    'test-results/theater-preview-opening-pixel7.png',
    errors,
  );
  await page.getByRole('button', { name: /我回來了。.*點圖接故事/ }).click();
  await captureReady(
    page,
    page.getByRole('button', { name: '聽外婆接下一句' }),
    'test-results/theater-preview-outcome-pixel7.png',
    errors,
  );
  const firstOutcomeWorld = await page.screenshot({ animations: 'disabled' });
  await page.getByRole('button', { name: '換另一句，看看不同結果' }).click();
  await page.getByRole('button', { name: /我有一點累。.*點圖接故事/ }).click();
  await captureReady(
    page,
    page.getByRole('button', { name: '聽外婆接下一句' }),
    'test-results/theater-preview-outcome-tired-pixel7.png',
    errors,
  );
  const tiredOutcomeWorld = await page.screenshot({ animations: 'disabled' });
  expect(firstOutcomeWorld.equals(tiredOutcomeWorld)).toBe(false);
  const openRelayPreview = page.getByRole('button', {
    name: '看這句怎麼傳回家',
  });
  await scrollUntilAttached(page, openRelayPreview);
  await openRelayPreview.click();
  await expect(page.getByText(/第 3 幕，共三幕：傳回家/)).toBeVisible();
  await expect(page.getByText('原來，一句話會這樣傳下來')).toBeVisible();
  await expect(page.getByText(/孩子帶回：我有一點累。/)).toBeVisible();
  await expect(page.getByText(/家人傳下：Cháu hơi mệt ạ\./)).toBeVisible();
  await expect(page.getByText(/孩子接住：外婆搬來軟墊/)).toBeVisible();
  await captureReady(
    page,
    page.getByText('原來，一句話會這樣傳下來'),
    'test-results/theater-preview-relay-pixel7.png',
    errors,
  );
  const relayAudio = page.getByRole('button', {
    name: '播放三棒接力',
  });
  await relayAudio.click();
  await expect(page.getByText('三棒接力完成 ✓')).toBeVisible();
  await expect(page.getByRole('button', { name: '重播三棒接力' }))
    .toBeVisible();
  const relayDisclosure = page.getByText(
    /Piper 合成操作示範.*不是真人原音.*未使用、建立或保存任何家庭資料/,
  );
  await scrollUntilAttached(page, relayDisclosure);
  await expect(relayDisclosure).toBeVisible();
  for (const seed of ['和家人分享', '社團', '午餐', '上課', '朋友關係']) {
    await expect(page.getByRole('checkbox', { name: seed })).toBeVisible();
  }
  await page.getByRole('checkbox', { name: '社團' }).click();
  await expect(page.getByText(/孩子想說｜我今天第一次參加社團。/))
    .toBeVisible();
  await expect(page.getByText(/系統不會自己猜翻譯/)).toBeVisible();
  const finishPreview = page.getByRole('button', {
    name: '同意後建立我們家的三棒故事',
  });
  await scrollUntilAttached(page, finishPreview);
  await finishPreview.click();
  await expect(page.getByText('先取得家人的同意')).toBeVisible();
  await establishFamilyCircle(page, errors);
  await page.getByRole('tab', { name: '選故事' }).click();
  const storyTeaser = page.getByRole('progressbar', {
    name: /把今天的事帶回家說/,
  });
  await scrollUntilAttached(page, storyTeaser);
  await captureReady(
    page,
    storyTeaser,
    'test-results/story-seeds-top-pixel7.png',
    errors,
  );
  await page.getByRole('button', { name: '社團' }).click();
  await captureReady(
    page,
    page.getByText('小米的第一棒'),
    'test-results/story-seed-intent-pixel7.png',
    errors,
  );
  await page.getByRole('button', {
    name: '我今天第一次參加社團',
  }).click();
  await captureReady(
    page,
    page.getByText('把「社團」交給家人'),
    'test-results/story-seed-handoff-pixel7.png',
    errors,
  );
  await page.getByRole('button', { name: '先不要' }).click();
  await page.getByRole('button', {
    name: /3 筆官方教材・課程・競賽入口/,
  }).click();
  await captureReady(
    page,
    page.getByText('傳家話只整理官方入口'),
    'test-results/education-opportunities-pixel7.png',
    errors,
  );
  await page.getByRole('button', { name: '關閉教育資訊' }).click();
  await page.getByRole('tab', { name: '劇場' }).click();
  await captureReady(
    page,
    page.getByRole('button', { name: /進入「放學回家」/ }),
    'test-results/theater-home-pixel7.png',
    errors,
  );

  await page.getByRole('button', { name: /進入「放學回家」/ }).click();
  const elderListen = page.getByRole('button', { name: '點一下，聽阿嬤說' });
  await expect(elderListen).toBeVisible();
  const elderListenBox = await elderListen.boundingBox();
  expect(elderListenBox).not.toBeNull();
  expect(elderListenBox.height).toBeGreaterThanOrEqual(44);
  await captureReady(
    page,
    page.getByRole('button', {
      name: /圖像選擇「我回來了。」/,
    }),
    'test-results/theater-opening-pixel7.png',
    errors,
  );

  const prepare = page.getByRole('button', {
    name: '圖像選擇「我回來了。」；選取後可以開口或直接繼續故事',
  });
  await scrollUntilAttached(page, prepare);
  await prepare.click();
  await captureReady(
    page,
    page.getByRole('button', { name: '慢速・逐段學' }),
    'test-results/theater-beginner-scaffold-pixel7.png',
    errors,
  );

  await page.getByRole('button', { name: '慢速・逐段學' }).click();
  await captureReady(
    page,
    page.getByText('慢慢聽這一句'),
    'test-results/theater-listening-tools-pixel7.png',
    errors,
  );
  await expect(page.getByRole('checkbox', { name: /cháu/ })).toBeVisible();
  await expect(page.getByRole('checkbox', { name: /^về rồi ạ$/ })).toBeVisible();
  await expect(page.getByRole('checkbox', { name: /^ạ$/ })).toHaveCount(0);
  await page.getByRole('button', { name: '關閉慢速聆聽' }).click();
  await expect(page.getByText('慢慢聽這一句')).toHaveCount(0);

  const listenSlot = page.getByRole('button', {
    name: /^(先聽整句|播放中.*)$/,
  });
  await scrollUntilAttached(page, listenSlot);
  const listen = page.getByRole('button', { name: '先聽整句' });
  try {
    await listen.waitFor({ state: 'visible', timeout: 3_000 });
    await listen.click();
  } catch (_) {
    await expect(page.getByRole('button', { name: /^播放中/ })).toBeDisabled();
  }
  const directSceneChoice = page.getByRole('button', {
    name: /不開麥克風，用這張圖讓.+回話/,
  });
  await captureReady(
    page,
    directSceneChoice,
    'test-results/theater-fallback-cards-pixel7.png',
    errors,
  );
  await directSceneChoice.click();
  const firstNext = page.getByRole('button', {
    name: /看接下來發生什麼|馬上接下去|我看完了，接著演/,
  });
  await scrollUntilAttached(page, firstNext);
  await expect(firstNext).toBeEnabled({ timeout: 20_000 });
  await captureReady(
    page,
    firstNext,
    'test-results/theater-reaction-pixel7.png',
    errors,
  );
  await firstNext.click();

  let next = await chooseByCard(page, '今天很開心。');
  await next.click();
  next = await chooseByCard(page, '好呀！');
  await next.click();
  await captureReady(
    page,
    page.getByText('我們把故事演完了！'),
    'test-results/theater-finale-pixel7.png',
    errors,
  );

  const bringHome = page.getByRole('button', { name: '帶著故事卡回家' });
  await scrollUntilAttached(page, bringHome);
  await bringHome.click();
  await page.getByRole('tab', { name: '家人圈' }).click();
  await captureReady(
    page,
    page.getByText('我們演過的故事'),
    'test-results/family-circle-pixel7.png',
    errors,
  );

  await unlockParent(page, errors);
  await page.getByRole('button', { name: /回應孩子的故事卡/ }).click();
  const proud = page.getByRole('checkbox', { name: '以你為榮' });
  await scrollUntilAttached(page, proud);
  await proud.click();
  const continueButton = page.getByRole('button', {
    name: '留一句，孩子下次會看到',
  });
  await scrollUntilAttached(page, continueButton);
  await continueButton.click();
  await page.getByRole('textbox', { name: '孩子下次會看到的話' })
    .fill('明天阿嬤還想聽你說一個新故事！');
  await page.getByRole('button', { name: '留給孩子' }).click();
  await captureReady(
    page,
    page.getByText('明天阿嬤還想聽你說一個新故事！'),
    'test-results/family-response-pixel7.png',
    errors,
  );

  expect(errors).toEqual([]);
});

test('Pixel 7 club seed completes the full family relay', async ({ page }) => {
  test.slow();
  await page.setViewportSize({ width: 412, height: 915 });
  const errors = [];
  page.on('pageerror', (error) =>
    errors.push(error.stack || `${error.name}: ${error.message}`));

  await openColdApp(page, errors);
  await establishFamilyCircle(page, errors);
  await completeClubFamilyRelayVisual(page, errors);

  expect(errors).toEqual([]);
});
