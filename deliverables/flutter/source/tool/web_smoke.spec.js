const { test, expect } = require('@playwright/test');

const baseURL = process.env.HOMETONGUE_URL || 'http://127.0.0.1:8766/';

test('release boot removes the legacy Flutter service worker', async ({ request }) => {
  const indexResponse = await request.get(baseURL);
  expect(indexResponse.ok()).toBeTruthy();
  const index = await indexResponse.text();
  expect(index).toContain('hometongue-sw-cleanup-v1');
  expect(index).toContain('registration.unregister()');

  const bootstrapResponse = await request.get(
    new URL('flutter_bootstrap.js', baseURL).toString(),
  );
  expect(bootstrapResponse.ok()).toBeTruthy();
  const bootstrap = await bootstrapResponse.text();
  // Flutter's generic loader class still contains the legacy option name;
  // pwa-strategy=none is represented by the actual boot call having no
  // service-worker configuration.
  expect(bootstrap.trim()).toMatch(/_flutter\.loader\.load\(\);$/);
  expect(bootstrap).not.toContain('_flutter.loader.load({');
});

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
  await page.keyboard.press('Tab');
  await afterPaint(page);
}

async function waitForDecodedImages(page) {
  const result = await page.evaluate(async () => {
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
    return {
      total: images.length,
      broken: images.filter((image) => image.complete && image.naturalWidth === 0)
        .map((image) => image.currentSrc || image.src),
    };
  });
  expect(result.broken, `broken image elements: ${result.broken.join(', ')}`).toEqual([]);
  await afterPaint(page);
}

async function openColdApp(page, errors) {
  await page.addInitScript(() => {
    window.__hometongueMediaEvents = [];
    const auditedAudioElements = new WeakSet();
    const auditAudioElement = (element) => {
      if (auditedAudioElements.has(element)) return element;
      auditedAudioElements.add(element);
      for (const type of ['play', 'playing', 'ended', 'error']) {
        element.addEventListener(type, () => {
          window.__hometongueMediaEvents.push({
            type,
            src: element.currentSrc || element.src || '',
            currentTime: element.currentTime,
            duration: Number.isFinite(element.duration) ? element.duration : null,
            readyState: element.readyState,
            networkState: element.networkState,
            paused: element.paused,
            ended: element.ended,
            errorCode: element.error?.code ?? null,
            errorMessage: element.error?.message ?? null,
          });
        });
      }
      return element;
    };
    const originalCreateElement = Document.prototype.createElement;
    Document.prototype.createElement = function createElementWithMediaAudit(
      name,
      options,
    ) {
      const element = originalCreateElement.call(this, name, options);
      if (String(name).toLowerCase() === 'audio') {
        auditAudioElement(element);
      }
      return element;
    };
    // just_audio currently creates its element through document.createElement,
    // but wrapping the native play boundary keeps the audit valid if the web
    // plugin switches to `new Audio()` in a later release. The original media
    // implementation still performs the actual playback.
    const originalMediaPlay = HTMLMediaElement.prototype.play;
    HTMLMediaElement.prototype.play = function playWithMediaAudit(...args) {
      if (this instanceof HTMLAudioElement || this.tagName === 'AUDIO') {
        auditAudioElement(this);
      }
      return originalMediaPlay.apply(this, args);
    };

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
    // Flutter removes this bootstrap button as soon as semantics becomes
    // active. It may disappear between count() and click(), which is already
    // a successful state rather than a test failure.
    await accessibility
      .evaluate((element) => element.click(), { timeout: 2_000 })
      .catch(() => {});
  }
  await expect(consent).toBeVisible();
  await waitForDecodedImages(page);
  expect(errors).toEqual([]);
}

function installMp3ResponseAudit(page, responses) {
  page.on('response', (response) => {
    const url = new URL(response.url());
    if (!url.pathname.toLowerCase().endsWith('.mp3')) return;
    responses.push({
      url: response.url(),
      status: response.status(),
      resourceType: response.request().resourceType(),
      fromServiceWorker: response.fromServiceWorker(),
    });
  });
}

async function playFirstElderLineAndWaitForEnded(
  page,
  elderName,
  mp3Responses,
) {
  await page.evaluate(() => {
    window.__hometongueMediaEvents.length = 0;
  });
  mp3Responses.length = 0;
  const listen = page.getByRole('button', {
    name: `點一下，聽${elderName}說`,
  });
  await scrollUntilAttached(page, listen);
  await expect(listen).toBeVisible();
  expect(await page.evaluate(() => window.__hometongueMediaEvents)).toEqual([]);

  await listen.click();
  await expect.poll(
    async () => page.evaluate(() =>
      window.__hometongueMediaEvents.some((event) => event.type === 'ended')),
    {
      message: 'the explicitly-clicked built-in MP3 should reach ended',
      timeout: 20_000,
    },
  ).toBe(true);

  const events = await page.evaluate(() => window.__hometongueMediaEvents);
  const eventTypes = events.map((event) => event.type);
  expect(eventTypes, JSON.stringify(events, null, 2)).not.toContain('error');
  expect(eventTypes).toContain('play');
  expect(eventTypes).toContain('playing');
  expect(eventTypes).toContain('ended');
  expect(eventTypes.indexOf('play')).toBeLessThan(eventTypes.indexOf('playing'));
  expect(eventTypes.indexOf('playing')).toBeLessThan(eventTypes.indexOf('ended'));
  const ended = events.find((event) => event.type === 'ended');
  expect(ended.duration, JSON.stringify(events, null, 2)).toBeGreaterThan(0);
  expect(ended.currentTime, JSON.stringify(events, null, 2)).toBeGreaterThan(0);
  await expect.poll(
    () => mp3Responses.some((response) => response.status === 200),
    {
      message: `expected a 200 response for the clicked MP3, got ${JSON.stringify(mp3Responses)}`,
      timeout: 5_000,
    },
  ).toBe(true);
  expect(
    mp3Responses.every((response) =>
      new URL(response.url).pathname.toLowerCase().endsWith('.mp3')),
  ).toBe(true);
  await expect(listen).toHaveCount(0);
}

async function acceptConsentAndCreateFamilyCircle(page, errors) {
  await openColdApp(page, errors);

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

  await expect(page.getByText('先建立你們家的小圈圈')).toBeVisible();
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
  await expect(page.getByRole('button', { name: /進入「放學回家」/ })).toBeVisible();
  await waitForDecodedImages(page);
  expect(errors).toEqual([]);
}

async function scrollUntilAttached(page, locator) {
  for (let index = 0; index < 18 && !(await locator.count()); index += 1) {
    await page.mouse.wheel(0, 430);
    await afterPaint(page);
  }
  await expect(locator).toBeAttached();
  await locator.scrollIntoViewIfNeeded();
  await afterPaint(page);
}

async function chooseWithBeginnerScaffold(page, choice) {
  const prepare = page.getByRole('button', {
    name: `準備「${choice.translation}」，這一步不會送出`,
  });
  await scrollUntilAttached(page, prepare);
  await prepare.click();

  const scaffold = page.getByRole('group', {
    name: new RegExp(choice.romanization.replaceAll('/', '\\/')),
  });
  await expect(scaffold).toBeVisible();
  await expect(scaffold).toHaveAccessibleName(new RegExp(choice.target));

  const listenSlot = page.getByRole('button', { name: /先聽這一句|正在播放/ });
  await scrollUntilAttached(page, listenSlot);
  const listen = page.getByRole('button', { name: '先聽這一句' });
  // Headless Edge can expose speechSynthesis without ever firing its end
  // callback. The explicit listening control is still verified above; click
  // it only when the platform reports that narration has finished.
  try {
    await listen.waitFor({ state: 'visible', timeout: 3_000 });
    await listen.click();
  } catch (_) {
    await expect(page.getByRole('button', { name: '正在播放' })).toBeDisabled();
  }

  const fallback = page.getByRole('button', { name: '今天先用小卡直接接故事' });
  await scrollUntilAttached(page, fallback);
  await fallback.click();
  const directChoice = page.getByRole('button', {
    name: `直接選擇：${choice.translation}`,
  });
  await scrollUntilAttached(page, directChoice);
  await directChoice.click();

  const next = page.getByRole('button', {
    name: /看接下來發生什麼|完成這一集|馬上接下去|馬上收好故事|我看完了，接著演/,
  });
  await scrollUntilAttached(page, next);
  await expect(next).toBeEnabled({ timeout: 20_000 });
  return next;
}

async function unlockParent(page) {
  await page.getByRole('button', { name: '交給家人', exact: true }).click();
  await page.getByRole('button', { name: '家庭管理者・出題與管理' }).click();
  await page.getByRole('textbox', { name: '四位數家長碼' }).fill('2468');
  await page.getByRole('button', { name: '確認' }).click();
  await expect(page.getByText('家人怎麼參與？')).toBeVisible();
}

const clubRelayTarget = 'Hôm nay con tham gia câu lạc bộ lần đầu';

async function completeClubFamilyRelay(page) {
  await page.getByRole('tab', { name: '選故事' }).click();
  await page.getByRole('button', { name: '社團' }).click();
  await expect(page.getByText('小米的第一棒')).toBeVisible();
  await page.getByRole('button', {
    name: '我今天第一次參加社團',
  }).click();

  await expect(page.getByText('把「社團」交給家人')).toBeVisible();
  await expect(page.getByText(/小米已經留下第一棒/)).toBeVisible();
  await page.getByRole('button', { name: '已交給家人' }).click();
  await page.getByRole('textbox', { name: '四位數家長碼' }).fill('2468');
  await page.getByRole('button', { name: '確認' }).click();

  await expect(page.getByRole('group', {
    name: /把「社團」變成四關故事任務/,
  })).toBeVisible();
  await expect(page.getByRole('group', {
    name: /孩子帶回的第一棒｜社團 我今天第一次參加社團。/,
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
  await expect(familyConfirmed).toBeChecked();
  const save = page.getByRole('button', { name: '建立並交給孩子闖四關' });
  await scrollUntilAttached(page, save);
  await save.click();

  await expect(page.getByText('回到家的時刻')).toBeVisible();
  await page.getByRole('button', { name: '回家的孩子', exact: true }).click();
  await page.getByRole('button', { name: '下一關' }).click();

  await expect(page.getByText('先看懂，再用耳朵找')).toBeVisible();
  const listen = page.getByRole('button', { name: /點一下聽/ });
  await scrollUntilAttached(page, listen);
  await listen.click();
  await expect(page.getByRole('button', { name: /再聽一次/ }))
    .toBeVisible();
  await page.getByRole('button', { name: '回家的孩子', exact: true }).click();
  await page.getByRole('button', { name: '下一關' }).click();

  await expect(page.getByText('排好句子')).toBeVisible();
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
    const word = page.getByText(token, { exact: true }).last();
    await word.scrollIntoViewIfNeeded();
    await word.click();
  }
  await expect(page.getByText(/句子排好了/)).toBeVisible();
  await page.getByRole('button', { name: '下一關' }).click();

  await expect(page.getByText('幫角色回答')).toBeVisible();
  const relayAnswer = page.getByRole('button', {
    name: new RegExp(clubRelayTarget),
  });
  await scrollUntilAttached(page, relayAnswer);
  await relayAnswer.click();
  await page.getByRole('button', { name: '看我的星星' }).click();
  await expect(page.getByText('你完成了！')).toBeVisible();
  await page.getByRole('button', { name: '收下星星，跟著說' }).click();

  await expect(page.getByText('最後一關 · 跟著說')).toBeVisible();
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

  await expect(page.getByText('三棒接成一個家的故事')).toBeVisible();
  await expect(page.getByText('孩子帶回')).toBeVisible();
  await expect(page.getByText('家人傳下')).toBeVisible();
  await expect(page.getByText('孩子接住')).toBeVisible();
  const playRelay = page.getByRole('button', { name: '一起播放我們的接力' });
  await scrollUntilAttached(page, playRelay);
  await playRelay.click();
  await expect(page.getByRole('button', { name: '一起播放我們的接力' }))
    .toBeVisible();
  await page.getByRole('button', { name: '收進家人圈' }).click();

  await page.getByRole('tab', { name: '家人圈' }).click();
  const relayCircleCard = page.getByText('三棒家庭接力');
  await scrollUntilAttached(page, relayCircleCard);
  await expect(relayCircleCard).toBeVisible();
  await expect(page.getByText(
    /家庭接力・社團[\s\S]*我今天第一次參加社團。[\s\S]*Hôm nay con tham gia câu lạc bộ lần đầu[\s\S]*用文字完成這一棒/,
  )).toBeVisible();
}

test('adult establishes the circle, child completes three turns, and family responds', async ({ page }) => {
  await page.setViewportSize({ width: 412, height: 915 });
  const errors = [];
  const mp3Responses = [];
  installMp3ResponseAudit(page, mp3Responses);
  page.on('pageerror', (error) => errors.push(error.stack || error.message));
  await acceptConsentAndCreateFamilyCircle(page, errors);

  await page.getByRole('button', { name: /進入「放學回家」/ }).click();
  await expect(page.getByText('家庭對話劇場')).toBeVisible();
  await playFirstElderLineAndWaitForEnded(page, '阿嬤', mp3Responses);
  await expect(page.getByRole('button', {
    name: /準備「我回來了。」，這一步不會送出/,
  })).toBeVisible();
  await expect(page.getByRole('button', { name: '先選意思才能開啟麥克風' }))
    .toBeDisabled();

  let next = await chooseWithBeginnerScaffold(page, {
    translation: '我回來了。',
    target: 'Cháu về rồi ạ.',
    romanization: 'cháu / về rồi / ạ',
  });
  await next.click();
  next = await chooseWithBeginnerScaffold(page, {
    translation: '今天很開心。',
    target: 'Hôm nay vui ạ.',
    romanization: 'hôm nay / vui / ạ',
  });
  await next.click();
  next = await chooseWithBeginnerScaffold(page, {
    translation: '好呀！',
    target: 'Vâng ạ!',
    romanization: 'vâng / ạ',
  });
  await next.click();

  await expect(page.getByText('我們把故事演完了！')).toBeVisible();
  await expect(page.getByText('今天的家庭故事卡')).toBeVisible();
  await expect(page.getByText('我回來了。', { exact: true })).toBeVisible();
  const home = page.getByRole('button', { name: '帶著故事卡回家' });
  await scrollUntilAttached(page, home);
  await home.click();

  await page.getByRole('tab', { name: '家人圈' }).click();
  await expect(page.getByText('我們家的故事圈')).toBeVisible();
  await expect(page.getByText('我們演過的故事')).toBeVisible();
  await expect(page.getByText('1 張')).toBeVisible();

  await unlockParent(page);
  await page.getByRole('button', { name: /回應孩子的故事卡/ }).click();
  await expect(page.getByText('回到故事裡陪孩子')).toBeVisible();

  const proud = page.getByRole('checkbox', { name: '以你為榮' });
  await scrollUntilAttached(page, proud);
  await proud.click();
  await expect(proud).toBeChecked();

  const continueButton = page.getByRole('button', {
    name: '留一句，孩子下次會看到',
  });
  await scrollUntilAttached(page, continueButton);
  await continueButton.click();
  const familyReply = '今天的故事我聽見了，明天再一起演！';
  await page.getByRole('textbox', { name: '孩子下次會看到的話' }).fill(familyReply);
  await page.getByRole('button', { name: '留給孩子' }).click();
  await expect(page.getByText(familyReply).last()).toBeVisible();

  await page.getByRole('button', { name: '離開家人模式' }).click();
  await page.getByRole('tab', { name: '家人圈' }).click();
  await expect(page.getByText(familyReply).last()).toBeVisible();
  expect(errors).toEqual([]);
});

test('five-story library and microphone repair keep a zero-beginner moving', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 800 });
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.stack || error.message));
  await acceptConsentAndCreateFamilyCircle(page, errors);

  await page.getByRole('tab', { name: '選故事' }).click();
  await expect(page.getByText('挑一集來演')).toBeVisible();
  await expect(page.getByRole('progressbar', {
    name: /把今天的事帶回家說/,
  })).toBeVisible();
  for (const seed of ['家人分享', '社團', '午餐', '上課', '朋友關係']) {
    await expect(page.getByRole('button', { name: seed })).toBeVisible();
  }
  await page.getByRole('button', { name: '社團' }).click();
  await expect(page.getByText('小米的第一棒')).toBeVisible();
  await page.getByRole('button', {
    name: '我今天第一次參加社團',
  }).click();
  await expect(page.getByText('把「社團」交給家人')).toBeVisible();
  await expect(page.getByText(/系統不會替家庭猜翻譯/)).toBeVisible();
  await page.getByRole('button', { name: '先不要' }).click();
  await page.getByRole('button', {
    name: /3 筆官方教材・課程・競賽入口/,
  }).click();
  await expect(page.getByText('傳家話只整理官方入口')).toBeVisible();
  await page.getByRole('button', { name: '關閉教育資訊' }).click();
  for (const title of [
    '放學回家',
    '早安！起床囉',
    '一起準備晚餐',
    '陽台澆花',
    '睡前故事',
  ]) {
    const episode = page.getByRole('button', { name: new RegExp(title) });
    await scrollUntilAttached(page, episode);
    await expect(episode).toBeVisible();
  }

  await page.getByRole('button', { name: /陽台澆花/ }).click();
  await expect(page.getByText('家庭對話劇場')).toBeVisible();
  await expect(page.getByRole('button', {
    name: /準備「我來澆花。」，這一步不會送出/,
  })).toBeVisible();
  await page.getByRole('button', {
    name: '準備「我來澆花。」，這一步不會送出',
  }).click();
  await expect(page.getByRole('group', { name: /cháu \/ tưới cây \/ ạ/ }))
    .toBeVisible();

  const microphone = page.getByRole('button', { name: '開啟麥克風說練習短句' });
  await scrollUntilAttached(page, microphone);
  await microphone.click();
  const directGardenChoice = page.getByRole('button', {
    name: '直接選擇：我來澆花。',
  });
  await expect(directGardenChoice).toBeVisible({ timeout: 20_000 });
  await expect(page.getByRole('group', {
    name: /聽不到你|麥克風還沒打開|沒聽清楚|聲音剛剛迷路/,
  })).toBeVisible();

  await page.getByRole('button', { name: 'Back' }).click();
  await unlockParent(page);
  await expect(page.getByText('用幾行話留一張短句')).toBeVisible();
  await expect(page.getByText('隱私與家庭資料')).toBeVisible();
  await expect(page.getByText(/串接設定/)).toHaveCount(0);
  expect(errors).toEqual([]);
});

test('club story seed completes the three-baton family relay', async ({ page }) => {
  test.slow();
  await page.setViewportSize({ width: 412, height: 915 });
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.stack || error.message));
  await acceptConsentAndCreateFamilyCircle(page, errors);

  await completeClubFamilyRelay(page);

  expect(errors).toEqual([]);
});

test('one-time invite requires personal acceptance before an adult can enter', async ({ page, context }) => {
  await page.setViewportSize({ width: 430, height: 900 });
  await context.grantPermissions(
    ['clipboard-read', 'clipboard-write'],
    { origin: new URL(baseURL).origin },
  );
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.stack || error.message));
  await acceptConsentAndCreateFamilyCircle(page, errors);

  await unlockParent(page);
  await page.getByRole('button', { name: /回應孩子的故事卡/ }).click();
  await expect(page.getByText('回到故事裡陪孩子')).toBeVisible();
  const addMember = page.getByRole('button', { name: '邀請或加入一位家人' });
  await scrollUntilAttached(page, addMember);
  await addMember.click();
  await typeFlutterText(
    page,
    page.getByRole('textbox', { name: '孩子怎麼叫他？' }),
    '阿公',
  );
  await typeFlutterText(
    page,
    page.getByRole('textbox', { name: '家庭關係' }),
    '外公',
  );
  await page.getByRole('button', { name: '做一份邀請包' }).click();
  await expect(page.getByText('把邀請親自交給 阿公')).toBeVisible();
  await page.getByRole('button', { name: '複製邀請包' }).click();
  const invitation = await page.evaluate(() => navigator.clipboard.readText());
  expect(invitation).toContain('hometongue-family-invitation-v1');
  expect(invitation).not.toContain('storyCards');
  await page.getByRole('button', { name: '關閉（遺失就重做）' }).click();

  await page.getByRole('button', { name: '離開家人模式' }).click();
  await page.getByRole('button', { name: '交給家人', exact: true }).click();
  await page.getByRole('button', { name: '我收到一份邀請' }).click();
  await page.getByRole('button', { name: '從剪貼簿貼上' }).click();
  await expect(page.getByText('我們家 邀請你以「阿公」加入')).toBeVisible();
  await typeFlutterText(
    page,
    page.getByRole('textbox', { name: '設定你的六位數家人碼' }),
    '135790',
  );
  await typeFlutterText(
    page,
    page.getByRole('textbox', { name: '再輸入一次家人碼' }),
    '135790',
  );
  await page.getByRole('checkbox', { name: /我就是受邀的 阿公/ }).click();
  await page.getByRole('button', { name: '接受，做回覆包' }).click();
  await expect(page.getByText('你已接受邀請')).toBeVisible({ timeout: 30_000 });
  await page.getByRole('button', { name: '複製回覆包並完成' }).click();
  const receipt = await page.evaluate(() => navigator.clipboard.readText());
  expect(receipt).toContain('hometongue-family-invitation-receipt-v1');
  expect(receipt).not.toContain('135790');

  await page.getByRole('button', { name: '交給家人', exact: true }).click();
  await page.getByRole('button', { name: '家庭管理者・出題與管理' }).click();
  await page.getByRole('textbox', { name: '四位數家長碼' }).fill('2468');
  await page.getByRole('button', { name: '確認' }).click();
  await expect(page.getByText('家人怎麼參與？')).toBeVisible();
  await page.getByRole('button', { name: /回應孩子的故事卡/ }).click();
  const importReceipt = page.getByRole('button', {
    name: '家人已接受：帶入回覆包',
  });
  await scrollUntilAttached(page, importReceipt);
  await importReceipt.click();
  await page.getByRole('button', { name: '從剪貼簿貼上' }).click();
  await page.getByRole('button', { name: '確認家人加入' }).click();
  await expect(page.getByText(/家人已正式加入/)).toBeVisible();

  await page.getByRole('button', { name: '離開家人模式' }).click();
  await page.getByRole('button', { name: '交給家人', exact: true }).click();
  await page.getByRole('button', { name: '已加入家人・回應故事' }).click();
  await page.getByRole('button', { name: /阿公.*外公/ }).click();
  await page.getByRole('textbox', { name: '阿公 的六位數家人碼' }).fill('135790');
  await page.getByRole('button', { name: '確認是 阿公' }).click();
  await expect(page.getByText('家人加戲 · 阿公')).toBeVisible({ timeout: 30_000 });
  await expect(page.getByRole('button', { name: '邀請或加入一位家人' }))
    .toHaveCount(0);
  expect(errors).toEqual([]);
});
