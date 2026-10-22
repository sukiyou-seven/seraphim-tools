# Seraphim Tools（Electron 版）

跨平台开发者工具箱，Electron 实现（macOS / Windows / Linux），与 macOS SwiftUI 原生版同源的工具思路。

![platform](https://img.shields.io/badge/platform-macOS%20%7C%20Windows%20%7C%20Linux-blue)
![release](https://img.shields.io/github/v/release/sukiyou-seven/seraphim-tools)
![license](https://img.shields.io/badge/license-MIT-green)

## 两个版本

这个仓库同时放两套实现：

- **Electron 版**（根目录）：跨平台，macOS / Windows / Linux，下面列的是这一套
- **macOS 原生版**（[`macos/`](macos/)）：SwiftUI 实现，17 个工具，最低 macOS 14，含 v2ray 代理、SSH 密钥、Git 助手、API 余额等需要系统能力的工具

macOS 原生版构建：

```bash
cd macos
./build.sh
```

详见 [`macos/README.md`](macos/README.md)。

## 工具清单（10 个）

| 工具 | 说明 |
|---|---|
| 🔲 二维码 | 文本转二维码（4 档纠错、PNG 下载）；图片/剪贴板反解（jsQR） |
| 🔁 编码解码 | Base64 / URL / Unicode 转义 / HTML 实体 / Hex 双向 + JWT 解码（含过期判断） |
| 🔐 加密解密 | MD5 / SHA-1 / SHA-256 / SHA-512 / HMAC（Node crypto）；AES-256-GCM 口令加解密（PBKDF2 150k 派生） |
| 📐 单位换算 | 长度 / 重量 / 温度 / 数据 / 面积 / 体积 / 速度 / 时间，含市制单位 |
| 🎲 生成器 | UUID v4 / v7（批量）、随机密码（字符集可选、防取模偏差）、随机字符串 |
| 🧰 开发辅助 | JSON 美化压缩校验、正则测试（高亮+分组明细）、时间戳/日期双向 |
| 🌐 网络工具 | 本机网卡、公网出口 IP（多源回退）、HTTP 请求测试（主进程发起无 CORS，状态/耗时/响应头/体） |
| 🎨 屏幕取色 | 截屏点选取色，RGB/HEX，历史色板一键复制 |
| 💬 提示词库 | 12 个分类模板，`{{变量}}` 占位替换，收藏 + 搜索 |
| 🖱️ 鼠标连点 | 鼠标连点（左/右/中键、单击/双击、跟随指针或固定坐标）/ 键盘连发（组合键、按住不放）；全局快捷键 F6 启停、F7 拾取位置 |

侧边栏按「常用 / 开发 / 桌面 / AI 创作」分组，深浅色主题可切换（默认跟随系统），所有状态本地持久化。

## 下载安装包

到 [Releases](https://github.com/sukiyou-seven/seraphim-tools/releases) 下载对应平台的安装包（由 GitHub Actions 自动构建）：

| 平台 | 文件 |
|---|---|
| macOS（Apple 芯片） | `SeraphimTools-1.0.0-mac-arm64.dmg` |
| macOS（Intel） | `SeraphimTools-1.0.0-mac-x64.dmg` |
| Windows（64 位） | `SeraphimTools-1.0.0-win-x64.exe` |
| Linux（64 位） | `SeraphimTools-1.0.0-linux-x86_64.AppImage` / `SeraphimTools-1.0.0-linux-amd64.deb` |

> 安装包**未签名**：macOS 首次打开请右键 →「打开」；Windows 的 SmartScreen 提示点「更多信息 → 仍要运行」。
> 推送 `v*` tag 会自动重新构建三个平台并上传到对应 Release；也可以在 Actions 里手动触发并指定 tag。

## 运行

```bash
npm install
npm start
```

> 鼠标连点（`@nut-tree-fork/nut-js`）需要系统级输入权限：
> - **macOS**：第一次点「开始」后系统会提示，到「系统设置 → 隐私与安全性 → 辅助功能」里勾上当前运行的程序（`npm start` 时是 **Electron**，打包后是工具箱）。没有授权时合成事件是静默失败的，页面会直接拦下。
> - **Windows**：一般无需额外授权；若被安全软件拦截需放行。
> - **Linux**：需要 X11（`xdotool`/XTest 由 nut-js 自带）。

> 国内网络安装 electron 二进制慢时：
> ```bash
> ELECTRON_MIRROR="https://npmmirror.com/mirrors/electron/" npm install
> ```

## 架构

- `main.js` — 主进程：窗口、IPC（哈希 / HTTP / 网卡 / 公网 IP / 截屏 / 连点）、全局热键
- `autoclick-engine.js` — 连点状态机（纯 Node，鼠标/键盘依赖注入，可脱离权限单测）
- `preload.js` — contextBridge 安全暴露，渲染进程不持 Node 权限
- `renderer/app.js` — 工具注册表 + 侧边栏路由 + 通用助手（el / copy / toast / store）
- `renderer/tools/*.js` — 每个工具一个文件，`Seraphim.register({...})` 即自动进侧边栏
- 连点事件由 `@nut-tree-fork/nut-js` 合成（跨平台，macOS 需辅助功能授权）
- CSP：`script-src 'self'`，无远程依赖，完全离线可用（公网 IP 查询除外）

### 新增一个工具

1. 在 `renderer/tools/` 新建 `mytool.js`
2. `Seraphim.register({ id, name, icon, category, desc, mount(root) { ... } })`
3. 在 `index.html` 加一行 `<script>`

## Roadmap

- [x] 鼠标连点 / 键盘连发 + 全局快捷键（v1.0.0）
- [ ] 更多 SwiftUI 版工具移植（v2ray 代理、SSH 密钥、Git 助手、API 余额等需要系统能力的工具）
- [ ] AI 驱动（接各家 OpenAI 兼容 API）
- [x] 打包分发（electron-builder → dmg / nsis / AppImage，GitHub Actions 自动构建）
- [ ] 原型助手（Mermaid 流程图）

## License

MIT
