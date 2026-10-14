// Seraphim Tools — preload（contextBridge 安全暴露）
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('seraphim', {
  qrcode: (text, ec, size) => ipcRenderer.invoke('qrcode', { text, ec, size }),
  hash: (algo, text, hmacKey) => ipcRenderer.invoke('hash', { algo, text, hmacKey }),
  http: (opts) => ipcRenderer.invoke('http', opts),
  netInterfaces: () => ipcRenderer.invoke('net-interfaces'),
  publicIP: () => ipcRenderer.invoke('public-ip'),
  screenThumbnail: (size) => ipcRenderer.invoke('screen-thumbnail', size),
  versions: () => ipcRenderer.invoke('versions')
});
