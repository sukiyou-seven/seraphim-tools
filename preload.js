// Seraphim Tools — preload（contextBridge 安全暴露）
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('seraphim', {
  qrcode: (text, ec, size) => ipcRenderer.invoke('qrcode', { text, ec, size }),
  hash: (algo, text, hmacKey) => ipcRenderer.invoke('hash', { algo, text, hmacKey }),
  http: (opts) => ipcRenderer.invoke('http', opts),
  netInterfaces: () => ipcRenderer.invoke('net-interfaces'),
  publicIP: () => ipcRenderer.invoke('public-ip'),
  screenThumbnail: (size) => ipcRenderer.invoke('screen-thumbnail', size),
  versions: () => ipcRenderer.invoke('versions'),

  // 鼠标连点 / 键盘连发
  autoclick: {
    state: () => ipcRenderer.invoke('autoclick:state'),
    start: (overrides) => ipcRenderer.invoke('autoclick:start', overrides),
    stop: () => ipcRenderer.invoke('autoclick:stop'),
    pick: () => ipcRenderer.invoke('autoclick:pick'),
    getConfig: () => ipcRenderer.invoke('autoclick:get-config'),
    setConfig: (patch) => ipcRenderer.invoke('autoclick:set-config', patch),
    permission: () => ipcRenderer.invoke('autoclick:permission'),
    requestPermission: () => ipcRenderer.invoke('autoclick:request-permission'),
    openPermissionSettings: () => ipcRenderer.invoke('autoclick:open-permission-settings'),

    /** 运行状态推送；返回取消订阅函数 */
    onState: (callback) => {
      const handler = (_event, state) => callback(state);
      ipcRenderer.on('autoclick:state', handler);
      return () => ipcRenderer.removeListener('autoclick:state', handler);
    },
    /** 全局热键拾取到坐标时推送 */
    onPicked: (callback) => {
      const handler = (_event, position) => callback(position);
      ipcRenderer.on('autoclick:picked', handler);
      return () => ipcRenderer.removeListener('autoclick:picked', handler);
    }
  }
});
