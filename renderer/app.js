// Seraphim Tools — 渲染进程核心：工具注册表 / 侧边栏路由 / 通用助手
(function () {
  'use strict';

  const registry = []; // { id, name, icon, category, desc, mount(root) }

  window.Seraphim = {
    register(def) { registry.push(def); },
    get tools() { return registry; },

    /** DOM 助手：el('div', {class:'x', onclick}, child...) */
    el(tag, attrs = {}, ...children) {
      const node = document.createElement(tag);
      for (const [k, v] of Object.entries(attrs)) {
        if (k === 'class') node.className = v;
        else if (k === 'style' && typeof v === 'object') Object.assign(node.style, v);
        else if (k.startsWith('on') && typeof v === 'function') node.addEventListener(k.slice(2), v);
        else if (v !== null && v !== undefined) node.setAttribute(k, v);
      }
      for (const c of children.flat()) {
        if (c === null || c === undefined) continue;
        node.append(c.nodeType ? c : document.createTextNode(c));
      }
      return node;
    },

    /** 复制到剪贴板 + toast */
    async copy(text, tip = '已复制') {
      try {
        await navigator.clipboard.writeText(text);
        Seraphim.toast(tip);
      } catch {
        Seraphim.toast('复制失败', true);
      }
    },

    toast(msg, isErr = false) {
      const layer = document.getElementById('toast-layer');
      const t = Seraphim.el('div', { class: 'toast' }, msg);
      if (isErr) t.style.background = 'var(--danger)', t.style.color = '#fff';
      layer.append(t);
      setTimeout(() => t.remove(), 1800);
    },

    /** localStorage JSON 存取 */
    store: {
      get(key, fallback) {
        try { const v = localStorage.getItem('st.' + key); return v === null ? fallback : JSON.parse(v); }
        catch { return fallback; }
      },
      set(key, val) { localStorage.setItem('st.' + key, JSON.stringify(val)); }
    },

    debounce(fn, ms = 250) {
      let t;
      return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); };
    }
  };

  // ---------- 侧边栏 + 路由 ----------
  const CATEGORY_ORDER = ['常用', '开发', '桌面', 'AI 创作'];

  function buildSidebar(current) {
    const nav = document.getElementById('tool-nav');
    nav.innerHTML = '';
    const groups = new Map();
    for (const t of registry) {
      if (!groups.has(t.category)) groups.set(t.category, []);
      groups.get(t.category).push(t);
    }
    const cats = [...groups.keys()].sort((a, b) =>
      (CATEGORY_ORDER.indexOf(a) + 99) - (CATEGORY_ORDER.indexOf(b) + 99));

    for (const cat of cats) {
      const group = Seraphim.el('div', { class: 'nav-group' },
        Seraphim.el('div', { class: 'nav-group-title' }, cat));
      for (const t of groups.get(cat)) {
        group.append(Seraphim.el('div', {
          class: 'nav-item' + (t.id === current ? ' active' : ''),
          onclick: () => { location.hash = t.id; }
        }, Seraphim.el('span', { class: 'icon' }, t.icon), t.name));
      }
      nav.append(group);
    }
  }

  function mountTool(id) {
    const tool = registry.find(t => t.id === id) || registry[0];
    if (!tool) return;
    buildSidebar(tool.id);
    const root = document.getElementById('tool-root');
    root.innerHTML = '';
    root.append(Seraphim.el('div', { class: 'tool-header' },
      Seraphim.el('div', { class: 'tool-title' }, tool.icon + ' ' + tool.name),
      Seraphim.el('div', { class: 'tool-desc' }, tool.desc || '')));
    tool.mount(root);
  }

  function route() {
    const id = decodeURIComponent(location.hash.replace('#', ''));
    mountTool(id);
  }
  window.addEventListener('hashchange', route);

  // ---------- 主题 ----------
  const themeBtn = () => document.getElementById('theme-toggle');
  function applyTheme(mode) {
    const sys = window.matchMedia('(prefers-color-scheme: dark)');
    const dark = mode === 'dark' || (mode === 'system' && sys.matches);
    document.documentElement.dataset.theme = dark ? 'dark' : 'light';
    const label = mode === 'dark' ? '🌙 深色' : mode === 'light' ? '☀️ 浅色' : '🌗 跟随系统';
    if (themeBtn()) themeBtn().textContent = label;
  }
  function cycleTheme() {
    const order = ['system', 'light', 'dark'];
    const cur = Seraphim.store.get('theme', 'system');
    const next = order[(order.indexOf(cur) + 1) % order.length];
    Seraphim.store.set('theme', next);
    applyTheme(next);
  }

  window.SeraphimBoot = async function () {
    applyTheme(Seraphim.store.get('theme', 'system'));
    window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
      if (Seraphim.store.get('theme', 'system') === 'system') applyTheme('system');
    });
    themeBtn().addEventListener('click', cycleTheme);

    try {
      const v = await window.seraphim.versions();
      document.getElementById('version-line').textContent =
        `v${v.app} · Electron ${v.electron}`;
    } catch { /* 忽略 */ }

    route();
  };
})();
