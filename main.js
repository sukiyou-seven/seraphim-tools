// Seraphim Tools — Electron 主进程
const { app, BrowserWindow, ipcMain, desktopCapturer, nativeTheme, shell } = require('electron');
const path = require('path');
const os = require('os');
const crypto = require('crypto');

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

app.whenReady().then(createWindow);
app.on('window-all-closed', () => app.quit());
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
