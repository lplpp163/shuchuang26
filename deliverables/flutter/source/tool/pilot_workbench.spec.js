const { test, expect } = require('@playwright/test');

const siteUrl = (process.env.SITE_URL || 'http://127.0.0.1:8765/').replace(/\/?$/, '/');

test('anonymous pilot workbench stays offline and aggregates only the fixed schema', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  const pageErrors = [];
  const unexpectedRequests = [];
  page.on('pageerror', (error) => pageErrors.push(String(error)));
  page.on('request', (request) => {
    if (request.resourceType() !== 'document') unexpectedRequests.push(request.url());
  });

  await page.goto(
    new URL('deliverables/pilot/evidence-workbench.html', siteUrl).href,
    { waitUntil: 'networkidle' },
  );
  await expect(page.getByRole('heading', { name: '匿名試辦彙整台' })).toBeVisible();
  await expect(page.getByText(/不等於學習成效.*母語正確性.*外部查核/)).toBeVisible();

  await page.getByText('技術安全檢查與內建自我測試', { exact: true }).click();
  await page.getByRole('button', { name: '執行內建自我檢查' }).click();
  await expect(page.locator('#selfTestResult')).toContainText('PASS 12／12');

  const samples = await page.evaluate(() => (
    window.__hometonguePilotWorkbench.getSyntheticSamples()
  ));
  await page.locator('#jsonInput').fill(JSON.stringify(samples));
  await page.getByRole('button', { name: '檢查並加入' }).click();
  await expect(page.locator('#acceptedCount')).toHaveText('2 份 cohort');
  await expect(page.locator('#startedTotal')).toHaveText('15');
  await expect(page.locator('#adultTotal')).toHaveText('11');
  await expect(page.locator('#completedTotal')).toHaveText('7');

  const evidence = await page.evaluate(() => {
    const workbench = window.__hometonguePilotWorkbench;
    const aggregate = workbench.getCurrentAggregate();
    const invalid = workbench.getSyntheticSamples()[0];
    invalid.school = '不應被接受';
    let piiRejected = false;
    try {
      workbench.normalizeSummary(invalid);
    } catch (error) {
      piiRejected = error && error.code === 'PII_KEY';
    }
    return { aggregate, piiRejected };
  });
  expect(evidence.piiRejected).toBe(true);
  expect(evidence.aggregate).toMatchObject({
    schema: 'hometongue-pilot-aggregate-v1',
    sourceSchema: 'hometongue-pilot-summary-v1',
    evidenceStatus: 'anonymous-self-reported-not-externally-verified',
    cohortsAccepted: 2,
    totals: { started: 15, adultCompleted: 11, completed: 7 },
    turnAveragePolicy: { status: 'not-aggregated' },
  });
  expect(evidence.aggregate.totals).not.toHaveProperty('adultTurnAverageSeconds');
  expect(evidence.aggregate.totals).not.toHaveProperty('childTurnAverageSeconds');

  const viewport = await page.evaluate(() => ({
    innerWidth,
    scrollWidth: document.documentElement.scrollWidth,
  }));
  expect(viewport.scrollWidth).toBeLessThanOrEqual(viewport.innerWidth);
  expect(unexpectedRequests).toEqual([]);
  expect(pageErrors).toEqual([]);
});
