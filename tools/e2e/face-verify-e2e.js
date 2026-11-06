/**
 * SP-3 人像到场核验 · 前端回归脚本（Playwright + Chromium 假摄像头）
 *
 * 真实链路：登录(RSA) → 会议页(真 LiveKit) → 开启 video 能力卡(真写库)
 *          → 勾同意 → 填当事人 ID → 开始核验 → 浏览器 canvas 抓帧 → 真调 ai-server
 *          → 服务端按 partyId 取证件照 + 累计窗口 → 真调 CompreFace → 卡片渲染
 *
 * 不 mock 任何接口。默认 MJPEG 假摄像头只替代「摄像头画面」用于 CI 回归；
 * 设 E2E_REAL_CAMERA=1 则关闭假设备参数、改用本机真实摄像头跑真人联调。
 * 真人真机门禁取证（G0/G1/G2）始终走 mediation-deploy/tools/g01/ 工具包，不用本脚本代替。
 * 需预先准备：该 partyId 在 ai_party_consent 有有效 FACE_COMPARE 同意，
 * 且身份底库的 idCardFrontUrl 指向可读文件；由 E2E_PARTY_ID 传入。
 */
const { chromium } = require('playwright-core');
const fs = require('fs');
const path = require('path');

const EXE = process.env.CHROME_EXE;
const BASE = process.env.BASE_URL || 'http://localhost:5173';
const SAMPLES = 'D:/work/mediation_platform/mediation-deploy/compreface/samples';
const MJPEG = path.join(SAMPLES, 'fake-cam.mjpeg');
const SHOTS = path.join(__dirname, 'shots');
const USER = process.env.E2E_USER || 'admin';
const PASS = process.env.E2E_PASS || 'admin123';
const ROOM_ID = process.env.E2E_ROOM || '1';
const PARTY_ID = process.env.E2E_PARTY_ID || '';
// 真人联调模式：去掉 Chromium 假摄像头参数，用本机真实摄像头；G0/G1 取证另走 tools/g01/
const REAL_CAM = process.env.E2E_REAL_CAMERA === '1';
if (!PARTY_ID) throw new Error('请设置 E2E_PARTY_ID：核验当事人的 partyId（须已有 FACE_COMPARE 单独同意）');

fs.mkdirSync(SHOTS, { recursive: true });
const log = (...a) => console.log('[e2e]', ...a);

(async () => {
  const camArgs = REAL_CAM
    ? ['--use-fake-ui-for-media-stream', '--autoplay-policy=no-user-gesture-required',
       '--no-sandbox', '--disable-dev-shm-usage']
    : ['--use-fake-device-for-media-stream', '--use-fake-ui-for-media-stream',
       `--use-file-for-fake-video-capture=${MJPEG}`,
       '--autoplay-policy=no-user-gesture-required', '--no-sandbox', '--disable-dev-shm-usage'];
  log(`摄像头模式：${REAL_CAM ? '真人摄像头（E2E_REAL_CAMERA=1）' : 'MJPEG 假摄像头（CI 回归）'}`);
  const browser = await chromium.launch({
    executablePath: EXE,
    args: camArgs,
  });
  const ctx = await browser.newContext({
    viewport: { width: 1600, height: 950 },
    permissions: ['camera', 'microphone'],
  });
  const page = await ctx.newPage();

  page.on('console', (m) => {
    if (m.type() === 'error') log('console.error:', m.text().slice(0, 200));
  });
  page.on('response', async (r) => {
    const u = r.url();
    if (u.includes('/ai/meeting/face/verify')) {
      let body = '';
      try { body = (await r.text()).slice(0, 400); } catch (e) { body = '<no body>'; }
      log('VERIFY HTTP', r.status(), body);
    }
    if (u.includes('/ai/meeting/analyze/toggle')) {
      let body = '';
      try { body = (await r.text()).slice(0, 200); } catch (e) { body = '<no body>'; }
      log('TOGGLE HTTP', r.status(), body);
    }
  });

  // ---------- 1. 登录 ----------
  await page.goto(`${BASE}/login`, { waitUntil: 'domcontentloaded' });
  await page.waitForSelector('input[placeholder="请输入账号"]', { timeout: 20000 });
  await page.fill('input[placeholder="请输入账号"]', USER);
  await page.fill('input[placeholder="请输入密码"]', PASS);
  await page.screenshot({ path: path.join(SHOTS, '01-login.png') });
  const submit = await page.$('form.login-form button[type=submit]');
  if (submit) {
    await submit.click();
  } else {
    await page.click('button:has-text("登 录"), button:has-text("登录")');
  }
  await page.waitForURL((u) => !u.pathname.includes('/login'), { timeout: 30000 });
  log('登录成功 ->', page.url());

  // ---------- 2. 进入会议页 ----------
  await page.goto(`${BASE}/ai/meeting/live?roomId=${ROOM_ID}&identity=${USER}&partyId=${PARTY_ID}`, {
    waitUntil: 'domcontentloaded',
  });
  await page.waitForTimeout(8000); // 等 LiveKit 连接 + 首帧
  const vids = await page.evaluate(() =>
    Array.from(document.querySelectorAll('video')).map((v) => ({
      w: v.videoWidth, h: v.videoHeight, id: v.id, cls: String(v.className || ''),
    })),
  );
  log('页面 video 元素:', JSON.stringify(vids));
  await page.screenshot({ path: path.join(SHOTS, '02-room.png') });

  // ---------- 3. 打开 AI 分析面板 ----------
  const tab = await page.$('button.tab[data-tab="analysis"]');
  if (!tab) throw new Error('未找到 AI 分析面板 tab');
  await tab.click();
  await page.waitForTimeout(1500);

  // ---------- 4. 开启 video 能力卡（服务端权威；已开启则不再点，避免误关） ----------
  const sw = await page.$('button.sw[data-sw="video"]');
  if (!sw) throw new Error('未找到 video 能力开关');
  log('video 开关 available=', await sw.getAttribute('data-available'),
      'pressed=', await sw.getAttribute('aria-pressed'),
      'disabled=', await sw.isDisabled());
  if ((await sw.getAttribute('aria-pressed')) !== 'true') {
    const perm = await page.$('#aPerm');
    if (perm && !(await perm.isHidden())) {
      await perm.click();
      await page.waitForTimeout(500);
      log('已点击演示权限切换');
    }
    if (!(await sw.isDisabled())) {
      await sw.click();
      await page.waitForTimeout(2500);
      log('点击开启后 pressed=', await sw.getAttribute('aria-pressed'));
    } else {
      log('开关不可点（前端权限码未同步）：依赖服务端已开启状态');
    }
  }

  // ---------- 5. 等待人像核验卡渲染（服务端 enabled 后需刷新能力状态） ----------
  try {
    await page.waitForSelector('div.fcard', { timeout: 8000 });
  } catch (e) {
    log('首次未见卡片，刷新页面重拉能力状态');
    await page.reload({ waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(8000);
    const tab2 = await page.$('button.tab[data-tab="analysis"]');
    if (tab2) { await tab2.click(); await page.waitForTimeout(1500); }
    await page.waitForSelector('div.fcard', { timeout: 20000 });
  }
  log('人像核验卡已渲染');

  // ---------- 6. 填当事人 ID + 勾同意 + 开始核验（证件照由服务端按 ID 取字节） ----------
  await page.fill('.fcard__file input[type=number]', PARTY_ID);
  await page.waitForTimeout(500);
  await page.check('label.fcard__consent input[type=checkbox]');
  await page.waitForTimeout(500);
  const btn = await page.$('.fcard__row button.mini');
  log('开始按钮 disabled=', await btn.isDisabled());
  await btn.click();

  // ---------- 7. 轮询核验结果 ----------
  let last = null;
  for (let i = 0; i < 20; i++) {
    await page.waitForTimeout(2000);
    const st = await page.evaluate(() => ({
      stage: document.querySelector('div.fcard')?.getAttribute('data-stage'),
      badge: document.querySelector('.fcard__badge')?.textContent?.trim(),
      sim: document.querySelector('.fcard__state .mono')?.textContent?.trim(),
      hint: document.querySelector('.fcard__hint')?.textContent?.trim(),
      msg: document.querySelector('.fcard__msg')?.textContent?.trim(),
      win: document.querySelector('.fcard__win')?.textContent?.trim(),
    }));
    last = st;
    log('状态', i, JSON.stringify(st));
    if (st.sim) break;
  }
  await page.screenshot({ path: path.join(SHOTS, '03-face-verify.png') });
  console.log('FINAL_STATE=' + JSON.stringify(last));
  await browser.close();
})().catch((e) => {
  console.error('[e2e] FAILED:', e && e.message ? e.message : e);
  process.exit(1);
});
