// Seraphim Tools — Electron 主进程
const { app, BrowserWindow, ipcMain, desktopCapturer, nativeTheme, shell,
  globalShortcut, systemPreferences } = require('electron');
const path = require('path');
const os = require('os');
const fs = require('fs');
const crypto = require('crypto');
const {
  AutoClickerEngine, DEFAULT_CONFIG, normalizeConfig, describeInterval
} = require('./autoclick-engine');

let win = null;

function createWindow() {
  win = new BrowserWindow({
    width: 1120,
    height: 780,
    minWidth: 860,
    minHeight: 600,
    title: 'Seraphim Tools 工具箱',
    backgroundColor: nativeTheme.shouldUseDarkColors ? '#14161b' : '#f4f5f7',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      spellcheck: false
    }
  });

  win.loadFile(path.join(__dirname, 'renderer', 'index.html'));

  // 调试钩子：ST_SHOT=/path/to.png 时启动后自动截图并退出（用于自动化验证）
  if (process.env.ST_SHOT) {
    win.webContents.once('did-finish-load', () => {
      if (process.env.ST_ROUTE)
        win.webContents.executeJavaScript(`location.hash='${process.env.ST_ROUTE}'`);
      setTimeout(async () => {
        try {
          const img = await win.webContents.capturePage();
          require('fs').writeFileSync(process.env.ST_SHOT, img.toPNG());
        } catch (e) { console.error('shot failed:', e); }
        app.quit();
      }, 1500);
    });
  }

  // 外部链接一律走系统浏览器
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (url.startsWith('http')) shell.openExternal(url);
    return { action: 'deny' };
  });
}

app.whenReady().then(() => {
  createWindow();
  initAutoClicker();
});
app.on('window-all-closed', () => app.quit());
app.on('will-quit', () => {
  // 连点还在跑就退出，合成事件会留在系统里；按键更要先松开
  if (autoEngine) autoEngine.stop();
  globalShortcut.unregisterAll();
});
app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) createWindow();
});

// ---------- IPC：二维码生成（qrcode 库仅在主进程可用） ----------
ipcMain.handle('qrcode', (_e, { text, ec = 'M', size = 384 }) =>
  new Promise((resolve, reject) => {
    require('qrcode').toDataURL(text, {
      errorCorrectionLevel: ec, width: Number(size), margin: 2
    }, (err, url) => err ? reject(err) : resolve(url));
  }));

// ---------- IPC：哈希 / HMAC（Node crypto） ----------
ipcMain.handle('hash', (_e, { algo, text, hmacKey }) => {
  const supported = ['md5', 'sha1', 'sha256', 'sha512'];
  if (!supported.includes(algo)) throw new Error('不支持的算法: ' + algo);
  if (hmacKey) {
    return crypto.createHmac(algo, hmacKey).update(text, 'utf8').digest('hex');
  }
  return crypto.createHash(algo).update(text, 'utf8').digest('hex');
});

// ---------- IPC：HTTP 请求测试（主进程 fetch，无 CORS 限制） ----------
ipcMain.handle('http', async (_e, { url, method = 'GET', headers = {}, body = null, timeoutMs = 20000 }) => {
  const started = Date.now();
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetch(url, {
      method,
      headers,
      body: ['GET', 'HEAD'].includes(method) ? undefined : body,
      signal: ctrl.signal,
      redirect: 'follow'
    });
    const text = await res.text();
    const headersObj = {};
    res.headers.forEach((v, k) => { headersObj[k] = v; });
    return {
      ok: res.ok,
      status: res.status,
      statusText: res.statusText,
      headers: headersObj,
      body: text.length > 512 * 1024 ? text.slice(0, 512 * 1024) + '\n…(已截断)' : text,
      ms: Date.now() - started
    };
  } catch (err) {
    return { ok: false, status: 0, statusText: '', headers: {}, body: '', ms: Date.now() - started,
      error: err.name === 'AbortError' ? `请求超时（${timeoutMs}ms）` : String(err.message || err) };
  } finally {
    clearTimeout(timer);
  }
});

// ---------- IPC：本机网络接口 ----------
ipcMain.handle('net-interfaces', () => {
  const out = [];
  for (const [name, addrs] of Object.entries(os.networkInterfaces())) {
    for (const a of addrs) {
      out.push({ name, address: a.address, family: a.family, internal: a.internal, mac: a.mac });
    }
  }
  return out;
});

// ---------- IPC：公网出口 IP（多源依次尝试） ----------
ipcMain.handle('public-ip', async () => {
  const sources = [
    ['https://api.ip.sb/geoip', j => ({ ip: j.ip, country: j.country, city: j.city })],
    ['https://ipapi.co/json/', j => ({ ip: j.ip, country: j.country_code, city: j.city })],
    ['https://ipwho.is/', j => ({ ip: j.ip, country: j.country_code, city: j.city })]
  ];
  for (const [url, pick] of sources) {
    try {
      const res = await fetch(url, { signal: AbortSignal.timeout(6000) });
      if (!res.ok) continue;
      return { source: url, ...pick(await res.json()) };
    } catch { /* 试下一个源 */ }
  }
  throw new Error('所有公网 IP 源均不可达');
});

// ---------- IPC：屏幕截图缩略图（取色用） ----------
ipcMain.handle('screen-thumbnail', async (_e, size = 1440) => {
  const sources = await desktopCapturer.getSources({
    types: ['screen'],
    thumbnailSize: { width: size, height: Math.round(size * 9 / 16) }
  });
  if (!sources.length) throw new Error('无法获取屏幕画面');
  return sources[0].thumbnail.toDataURL();
});

ipcMain.handle('versions', () => ({
  app: app.getVersion(),
  electron: process.versions.electron,
  chrome: process.versions.chrome,
  node: process.versions.node,
  platform: process.platform
}));

// ---------- 自动连点（鼠标连点 / 键盘连发） ----------
//
// 鼠标和键盘用 @nut-tree-fork/nut-js 合成真实事件（跨平台）。macOS 上需要
// 「辅助功能」授权，授予对象是当前运行的程序（开发时是 Electron，打包后是工具箱）。

let autoConfig = Object.assign({}, DEFAULT_CONFIG);
let autoEngine = null;
let autoRunning = false;
let autoFired = 0;
let autoLastError = null;
let autoHotkeys = { toggle: null, pick: null };

function autoConfigPath() {
  return path.join(app.getPath('userData'), 'autoclick.json');
}

function loadAutoConfig() {
  try {
    const raw = fs.readFileSync(autoConfigPath(), 'utf8');
    return normalizeConfig(Object.assign({}, DEFAULT_CONFIG, JSON.parse(raw)));
  } catch {
    return Object.assign({}, DEFAULT_CONFIG);
  }
}

function saveAutoConfig() {
  try {
    fs.mkdirSync(path.dirname(autoConfigPath()), { recursive: true });
    fs.writeFileSync(autoConfigPath(), JSON.stringify(autoConfig, null, 2));
  } catch (error) {
    console.error('保存连点配置失败:', error);
  }
}

function ensureAutoEngine() {
  if (autoEngine) return autoEngine;
  const nut = require('@nut-tree-fork/nut-js');
  autoEngine = new AutoClickerEngine({
    mouse: nut.mouse,
    keyboard: nut.keyboard,
    Point: nut.Point,
    Button: nut.Button,
    Key: nut.Key,
    onProgress(fired) {
      autoFired = fired;
      autoRunning = true;
      broadcastAutoState();
    },
    onFinish(fired) {
      autoFired = fired;
      autoRunning = false;
      broadcastAutoState();
    }
  });
  return autoEngine;
}

function autoPermission() {
  if (process.platform !== 'darwin') return { granted: true, platform: process.platform };
  return {
    granted: systemPreferences.isTrustedAccessibilityClient(false),
    platform: process.platform
  };
}

function autoState() {
  return {
    running: autoRunning,
    fired: autoFired,
    config: autoConfig,
    permission: autoPermission(),
    hotkeys: autoHotkeys,
    interval: describeInterval(autoConfig),
    lastError: autoLastError,
    platform: process.platform
  };
}

function broadcastAutoState() {
  if (win && !win.isDestroyed()) {
    win.webContents.send('autoclick:state', autoState());
  }
}

function startAutoClicker(overrides) {
  const permission = autoPermission();
  if (!permission.granted) {
    return {
      ok: false,
      error: '需要「辅助功能」权限：系统设置 → 隐私与安全性 → 辅助功能，把当前运行的程序（开发时是 Electron，打包后是工具箱）勾上。'
    };
  }
  if (autoRunning) return { ok: true };

  const config = normalizeConfig(Object.assign({}, autoConfig, overrides || {}));
  try {
    ensureAutoEngine().start(config);
  } catch (error) {
    autoLastError = error.message;
    return { ok: false, error: error.message };
  }

  autoConfig = config;
  saveAutoConfig();
  autoRunning = true;
  autoFired = 0;
  autoLastError = null;
  if (autoConfig.soundFeedback) { try { shell.beep(); } catch { /* 没声音也不影响 */ } }
  broadcastAutoState();
  return { ok: true };
}

function stopAutoClicker() {
  if (autoEngine) autoEngine.stop();
  const wasRunning = autoRunning;
  autoRunning = false;
  if (wasRunning && autoConfig.soundFeedback) { try { shell.beep(); } catch { /* 忽略 */ } }
  broadcastAutoState();
  return { ok: true };
}

function toggleAutoClicker() {
  return autoRunning ? stopAutoClicker() : startAutoClicker();
}

async function pickAutoPosition() {
  try {
    const nut = require('@nut-tree-fork/nut-js');
    const position = await nut.mouse.getPosition();
    autoConfig.fixedX = position.x;
    autoConfig.fixedY = position.y;
    autoConfig.positionMode = 'fixed';
    saveAutoConfig();
    if (win && !win.isDestroyed()) {
      win.webContents.send('autoclick:picked', { x: position.x, y: position.y });
    }
    broadcastAutoState();
    if (autoConfig.soundFeedback) { try { shell.beep(); } catch { /* 忽略 */ } }
    return { ok: true, x: position.x, y: position.y };
  } catch (error) {
    return { ok: false, error: error.message };
  }
}

function applyAutoHotkeys() {
  const result = { toggle: null, pick: null };
  try {
    globalShortcut.unregisterAll();
    if (autoConfig.hotKeyEnabled && autoConfig.hotKey) {
      result.toggle = globalShortcut.register(autoConfig.hotKey, () => toggleAutoClicker());
    }
    if (autoConfig.pickHotKeyEnabled && autoConfig.pickHotKey) {
      result.pick = globalShortcut.register(autoConfig.pickHotKey, () => { pickAutoPosition(); });
    }
  } catch (error) {
    autoLastError = '热键注册失败：' + error.message;
  }
  autoHotkeys = result;
  broadcastAutoState();
  return result;
}

function initAutoClicker() {
  autoConfig = loadAutoConfig();
  applyAutoHotkeys();
}

ipcMain.handle('autoclick:state', () => autoState());
ipcMain.handle('autoclick:start', (_e, overrides) => startAutoClicker(overrides));
ipcMain.handle('autoclick:stop', () => stopAutoClicker());
ipcMain.handle('autoclick:pick', () => pickAutoPosition());
ipcMain.handle('autoclick:get-config', () => autoConfig);
ipcMain.handle('autoclick:set-config', (_e, patch) => {
  autoConfig = normalizeConfig(Object.assign({}, autoConfig, patch || {}));
  saveAutoConfig();
  applyAutoHotkeys();
  return autoConfig;
});
ipcMain.handle('autoclick:permission', () => autoPermission());
ipcMain.handle('autoclick:request-permission', () => {
  if (process.platform === 'darwin') {
    systemPreferences.isTrustedAccessibilityClient(true);
  }
  return autoPermission();
});
ipcMain.handle('autoclick:open-permission-settings', () => {
  if (process.platform === 'darwin') {
    shell.openExternal('x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility');
  }
  return { ok: true };
});
