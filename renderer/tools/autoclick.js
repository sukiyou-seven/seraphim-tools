// 鼠标连点 / 键盘连发（Electron 版）
//
// 事件合成在主进程（nut-js），这里只负责配置和状态展示。运行中切到别的 App
// 也照点；启停和「拾取指针位置」都有全局快捷键。
Seraphim.register({
  id: 'autoclick',
  name: '鼠标连点',
  icon: '🖱️',
  category: '桌面',
  desc: '鼠标连点 / 键盘连发，全局快捷键启停',

  mount(root) {
    const api = window.seraphim.autoclick;
    const state = {
      config: null,
      running: false,
      fired: 0,
      permission: { granted: true, platform: 'darwin' },
      interval: '',
      lastError: null
    };

    // ---------- 小工具 ----------
    const MODIFIER_LABELS = { command: '⌘', shift: '⇧', option: '⌥', control: '⌃' };
    const SPECIAL_KEYS = {
      Space: 'Space', Enter: 'Enter', Escape: 'Esc', Tab: 'Tab', Backspace: 'Delete',
      Delete: 'Delete', ArrowLeft: '←', ArrowRight: '→', ArrowUp: '↑', ArrowDown: '↓',
      Home: 'Home', End: 'End', PageUp: 'Page Up', PageDown: 'Page Down'
    };

    function keyDisplay(event) {
      if (SPECIAL_KEYS[event.code]) return SPECIAL_KEYS[event.code];
      if (/^Key[A-Z]$/.test(event.code)) return event.code.slice(3);
      if (/^Digit\d$/.test(event.code)) return event.code.slice(5);
      if (/^F\d{1,2}$/.test(event.code)) return event.code;
      return event.key ? event.key.toUpperCase() : event.code;
    }

    function modifierList(event) {
      const list = [];
      if (event.metaKey) list.push('command');
      if (event.ctrlKey) list.push('control');
      if (event.altKey) list.push('option');
      if (event.shiftKey) list.push('shift');
      return list;
    }

    function chordDisplay(chord) {
      return (chord.modifiers || []).map(m => MODIFIER_LABELS[m] || '').join('')
        + (chord.display || chord.code || '未设置');
    }

    function toAccelerator(event) {
      let main = null;
      if (/^Key[A-Z]$/.test(event.code)) main = event.code.slice(3);
      else if (/^Digit\d$/.test(event.code)) main = event.code.slice(5);
      else if (/^F([1-9]|1\d|20)$/.test(event.code)) main = event.code;
      else {
        main = {
          Space: 'Space', Enter: 'Return', Escape: 'Escape', Tab: 'Tab',
          Backspace: 'Backspace', Delete: 'Delete', ArrowLeft: 'Left', ArrowRight: 'Right',
          ArrowUp: 'Up', ArrowDown: 'Down', Home: 'Home', End: 'End',
          PageUp: 'PageUp', PageDown: 'PageDown'
        }[event.code] || null;
      }
      if (!main) return null;
      const parts = [];
      if (event.metaKey) parts.push('CommandOrControl');
      if (event.ctrlKey) parts.push('Control');
      if (event.altKey) parts.push('Alt');
      if (event.shiftKey) parts.push('Shift');
      parts.push(main);
      return parts.join('+');
    }

    function acceleratorDisplay(accelerator) {
      if (!accelerator) return '未设置';
      const labels = { CommandOrControl: '⌘', Command: '⌘', Control: '⌃', Alt: '⌥', Shift: '⇧' };
      return accelerator.split('+').map(part => labels[part] || part).join('');
    }

    function numField(value, min, max, step) {
      return Seraphim.el('input', {
        type: 'number', value: String(value), min: String(min), max: String(max),
        step: String(step || 1), style: { width: '110px' }
      });
    }

    function setIfIdle(input, value) {
      if (document.activeElement !== input) input.value = String(value);
    }

    function selectField(options, value) {
      return Seraphim.el('select', {}, ...options.map(([val, label]) =>
        Seraphim.el('option', { value: val, ...(val === value ? { selected: 'selected' } : {}) }, label)));
    }

    // ---------- 配置读写 ----------
    let patching = null;
    async function patch(changes) {
      patching = true;
      try {
        const next = await api.setConfig(changes);
        state.config = next;
        render();
      } finally {
        patching = false;
      }
    }

    // ---------- 状态卡 ----------
    const statusDot = Seraphim.el('span', { class: 'status-dot' });
    const statusTitle = Seraphim.el('div', { style: { fontSize: '15px', fontWeight: '600' } }, '空闲');
    const statusDetail = Seraphim.el('div', { class: 'muted' }, '');
    const toggleBtn = Seraphim.el('button', { class: 'btn', onclick: toggle });
    const statusError = Seraphim.el('div', { class: 'err', style: { marginTop: '8px', display: 'none' } });
    const tagRow = Seraphim.el('div', { class: 'btn-row', style: { marginTop: '10px' } });

    const statusCard = Seraphim.el('div', { class: 'card' },
      Seraphim.el('h3', {}, '连点控制'),
      Seraphim.el('div', { class: 'row', style: { alignItems: 'center' } },
        Seraphim.el('div', { style: { display: 'flex', alignItems: 'center', gap: '12px' } },
          statusDot,
          Seraphim.el('div', {}, statusTitle, statusDetail)),
        Seraphim.el('div', {}, toggleBtn)),
      statusError,
      tagRow);

    // ---------- 目标卡 ----------
    const targetSelect = selectField([['mouse', '鼠标连点'], ['keyboard', '键盘连发']], 'mouse');
    const buttonSelect = selectField([['left', '左键'], ['right', '右键'], ['middle', '中键']], 'left');
    const styleSelect = selectField([['single', '单击'], ['double', '双击']], 'single');
    const pressInput = numField(30, 0, 2000, 5);
    const keyBtn = Seraphim.el('button', { class: 'btn secondary', onclick: captureTargetKey }, 'A');
    const holdCheck = Seraphim.el('input', { type: 'checkbox' });

    const mouseGroup = Seraphim.el('div', {},
      Seraphim.el('label', { class: 'fld' }, '按键'),
      buttonSelect,
      Seraphim.el('label', { class: 'fld' }, '点击方式'),
      styleSelect);

    const keyGroup = Seraphim.el('div', {},
      Seraphim.el('label', { class: 'fld' }, '要连发的键'),
      Seraphim.el('div', { class: 'row' },
        keyBtn,
        Seraphim.el('label', { class: 'muted', style: { display: 'flex', alignItems: 'center', gap: '6px' } },
          holdCheck, '按住不放（不自动松开）')));

    const targetCard = Seraphim.el('div', { class: 'card' },
      Seraphim.el('h3', {}, '连点目标'),
      targetSelect,
      mouseGroup,
      keyGroup,
      Seraphim.el('label', { class: 'fld' }, '按下到松开（毫秒）'),
      pressInput,
      Seraphim.el('div', { class: 'muted' },
        '按下时长就是按住多久才松手。老式 App 和游戏对过短的点击可能不认账，20–50 毫秒最稳；双击会连发两轮按下/松开。'));

    // ---------- 位置卡 ----------
    const positionSelect = selectField([['cursor', '跟随指针'], ['fixed', '固定位置']], 'cursor');
    const xInput = numField(0, -100000, 100000, 1);
    const yInput = numField(0, -100000, 100000, 1);
    const moveCheck = Seraphim.el('input', { type: 'checkbox', checked: 'checked' });
    const pickBtn = Seraphim.el('button', { class: 'btn secondary', onclick: toggleCountdown }, '取指针位置');
    const fixedGroup = Seraphim.el('div', {},
      Seraphim.el('div', { class: 'row' },
        Seraphim.el('div', {}, Seraphim.el('label', { class: 'fld' }, 'X'), xInput),
        Seraphim.el('div', {}, Seraphim.el('label', { class: 'fld' }, 'Y'), yInput),
        Seraphim.el('div', { class: 'muted', style: { display: 'flex', alignItems: 'flex-end', paddingBottom: '8px' } }, pickBtn)),
      Seraphim.el('label', { class: 'muted', style: { display: 'flex', alignItems: 'center', gap: '6px', marginTop: '8px' } },
        moveCheck, '每次点击前把指针移到这个位置'));

    const positionCard = Seraphim.el('div', { class: 'card' },
      Seraphim.el('h3', {}, '点击位置'),
      positionSelect,
      fixedGroup,
      Seraphim.el('div', { class: 'muted', style: { marginTop: '8px' } },
        '「取指针位置」有 3 秒倒计时，把指针移到目标点等它自动记；也可以直接按拾取热键（默认 F7），按一下记当前位置。'));

    // ---------- 节奏卡 ----------
    const intervalInput = numField(100, 10, 60000, 10);
    const randomCheck = Seraphim.el('input', { type: 'checkbox' });
    const randomMin = numField(80, 10, 60000, 10);
    const randomMax = numField(120, 10, 60000, 10);
    const randomGroup = Seraphim.el('div', { class: 'row' },
      Seraphim.el('div', {}, Seraphim.el('label', { class: 'fld' }, '最小间隔（毫秒）'), randomMin),
      Seraphim.el('div', {}, Seraphim.el('label', { class: 'fld' }, '最大间隔（毫秒）'), randomMax));
    const repeatSelect = selectField([['infinite', '一直运行'], ['count', '点 N 次']], 'infinite');
    const countInput = numField(100, 1, 10000000, 1);
    const countWrap = Seraphim.el('div', {}, Seraphim.el('label', { class: 'fld' }, '次数'), countInput);

    const rhythmCard = Seraphim.el('div', { class: 'card' },
      Seraphim.el('h3', {}, '节奏'),
      Seraphim.el('label', { class: 'fld' }, '间隔（毫秒）'),
      intervalInput,
      Seraphim.el('label', { class: 'muted', style: { display: 'flex', alignItems: 'center', gap: '6px', marginTop: '8px' } },
        randomCheck, '间隔在区间里随机'),
      randomGroup,
      Seraphim.el('label', { class: 'fld', style: { marginTop: '8px' } }, '运行方式'),
      repeatSelect,
      countWrap);

    // ---------- 热键卡 ----------
    const toggleKeyBtn = Seraphim.el('button', { class: 'btn secondary', onclick: () => captureHotkey('hotKey', toggleKeyBtn) });
    const pickKeyBtn = Seraphim.el('button', { class: 'btn secondary', onclick: () => captureHotkey('pickHotKey', pickKeyBtn) });
    const toggleKeyCheck = Seraphim.el('input', { type: 'checkbox', checked: 'checked' });
    const pickKeyCheck = Seraphim.el('input', { type: 'checkbox', checked: 'checked' });
    const soundCheck = Seraphim.el('input', { type: 'checkbox' });

    const hotkeyCard = Seraphim.el('div', { class: 'card' },
      Seraphim.el('h3', {}, '全局快捷键'),
      Seraphim.el('label', { class: 'fld' }, '开始 / 停止'),
      Seraphim.el('div', { class: 'row', style: { alignItems: 'center' } },
        toggleKeyBtn,
        Seraphim.el('label', { class: 'muted', style: { display: 'flex', alignItems: 'center', gap: '6px' } },
          toggleKeyCheck, '启用')),
      Seraphim.el('label', { class: 'fld', style: { marginTop: '8px' } }, '拾取指针位置'),
      Seraphim.el('div', { class: 'row', style: { alignItems: 'center' } },
        pickKeyBtn,
        Seraphim.el('label', { class: 'muted', style: { display: 'flex', alignItems: 'center', gap: '6px' } },
          pickKeyCheck, '启用')),
      Seraphim.el('label', { class: 'muted', style: { display: 'flex', alignItems: 'center', gap: '6px', marginTop: '10px' } },
        soundCheck, '启停和拾取时给个提示音'),
      Seraphim.el('div', { class: 'muted', style: { marginTop: '8px' } },
        '两条都全局生效：切到别的 App 也能用。要带 ⌘⌃⌥⇧ 修饰键，或者用 F1–F20 / 方向键，否则会把正常打字吃掉。'));

    // ---------- 权限卡 ----------
    const permissionBox = Seraphim.el('div', {});
    const permissionCard = Seraphim.el('div', { class: 'card' },
      Seraphim.el('h3', {}, '权限与说明'),
      permissionBox,
      Seraphim.el('div', { class: 'muted', style: { marginTop: '10px', lineHeight: '1.7' } },
        '原理：用 nut-js 合成真实的鼠标 / 键盘事件，所以能给别的 App 用——代价是系统级授权。' +
        'macOS 第一次要点「请求授权」，在「隐私与安全性 → 辅助功能」里勾上当前运行的程序（开发时是 Electron，打包后是工具箱）。' +
        '系统安全输入框、锁屏、部分全屏游戏的独占输入会忽略合成事件，这是系统限制。'));

    root.append(statusCard, targetCard, positionCard, rhythmCard, hotkeyCard, permissionCard);

    // ---------- 输入事件 ----------
    targetSelect.addEventListener('change', () => patch({ target: targetSelect.value }));
    buttonSelect.addEventListener('change', () => patch({ button: buttonSelect.value }));
    styleSelect.addEventListener('change', () => patch({ clickStyle: styleSelect.value }));
    pressInput.addEventListener('change', () => patch({ pressMs: Number(pressInput.value) }));
    holdCheck.addEventListener('change', () => patch({ holdKey: holdCheck.checked }));

    positionSelect.addEventListener('change', () => patch({ positionMode: positionSelect.value }));
    xInput.addEventListener('change', () => patch({ fixedX: Number(xInput.value) }));
    yInput.addEventListener('change', () => patch({ fixedY: Number(yInput.value) }));
    moveCheck.addEventListener('change', () => patch({ movePointer: moveCheck.checked }));

    intervalInput.addEventListener('change', () => patch({ intervalMs: Number(intervalInput.value) }));
    randomCheck.addEventListener('change', () => patch({ randomize: randomCheck.checked }));
    randomMin.addEventListener('change', () => patch({ randomMinMs: Number(randomMin.value) }));
    randomMax.addEventListener('change', () => patch({ randomMaxMs: Number(randomMax.value) }));
    repeatSelect.addEventListener('change', () => patch({ repeatMode: repeatSelect.value }));
    countInput.addEventListener('change', () => patch({ count: Number(countInput.value) }));

    toggleKeyCheck.addEventListener('change', () => patch({ hotKeyEnabled: toggleKeyCheck.checked }));
    pickKeyCheck.addEventListener('change', () => patch({ pickHotKeyEnabled: pickKeyCheck.checked }));
    soundCheck.addEventListener('change', () => patch({ soundFeedback: soundCheck.checked }));

    // ---------- 按键捕获 ----------
    function captureTargetKey() {
        const label = keyBtn.textContent;
        keyBtn.textContent = '请按键…（Esc 取消）';
        const handler = event => {
          event.preventDefault();
          event.stopPropagation();
          window.removeEventListener('keydown', handler, true);
          keyBtn.textContent = label;
          if (event.code === 'Escape') return;
          patch({ key: { code: event.code, display: keyDisplay(event), modifiers: modifierList(event) } });
        };
        window.addEventListener('keydown', handler, true);
    }

    function captureHotkey(field, button) {
      const label = button.textContent;
      button.textContent = '请按组合键…（Esc 取消）';
      const handler = event => {
        event.preventDefault();
        event.stopPropagation();
        window.removeEventListener('keydown', handler, true);
        button.textContent = label;
        if (event.code === 'Escape') return;
        const accelerator = toAccelerator(event);
        if (!accelerator) {
          Seraphim.toast('这个键不能当全局快捷键，换一个', true);
          return;
        }
        const hasModifier = event.metaKey || event.ctrlKey || event.altKey || event.shiftKey;
        if (!hasModifier && !/^F([1-9]|1\d|20)$/.test(event.code)) {
          Seraphim.toast('全局快捷键要带 ⌘⌃⌥⇧，或者用 F1–F20', true);
          return;
        }
        patch({ [field]: accelerator });
      };
      window.addEventListener('keydown', handler, true);
    }

    // ---------- 倒计时拾取 ----------
    let countdownTimer = null;
    function toggleCountdown() {
      if (countdownTimer) { cancelCountdown(); return; }
      let remaining = 3;
      pickBtn.textContent = remaining + ' 秒后取指针位置 · 取消';
      countdownTimer = setInterval(async () => {
        remaining -= 1;
        if (remaining > 0) {
          pickBtn.textContent = remaining + ' 秒后取指针位置 · 取消';
          return;
        }
        cancelCountdown();
        const result = await api.pick();
        if (result.ok) Seraphim.toast('已记录坐标 (' + result.x + ', ' + result.y + ')');
        else Seraphim.toast('取指针位置失败：' + (result.error || '未知错误'), true);
      }, 1000);
    }
    function cancelCountdown() {
      if (countdownTimer) clearInterval(countdownTimer);
      countdownTimer = null;
      pickBtn.textContent = '取指针位置';
    }

    // ---------- 启停 ----------
    async function toggle() {
      if (state.running) { await api.stop(); return; }
      const result = await api.start();
      if (!result.ok) {
        stateError(result.error);
        if (state.permission && state.permission.platform === 'darwin') {
          // 没权限时把入口摆到眼前，不自动弹系统框
          Seraphim.toast('先给「辅助功能」权限再开始', true);
        }
      }
    }

    function stateError(message) {
      state.lastError = message || null;
      statusError.textContent = message || '';
      statusError.style.display = message ? 'block' : 'none';
    }

    // ---------- 渲染 ----------
    function render(next) {
      if (next) {
        if (next.config) state.config = next.config;
        if (typeof next.running === 'boolean') state.running = next.running;
        if (typeof next.fired === 'number') state.fired = next.fired;
        if (next.permission) state.permission = next.permission;
        if (typeof next.interval === 'string') state.interval = next.interval;
        if (next.lastError !== undefined) state.lastError = next.lastError;
        if (next.hotkeys) state.hotkeys = next.hotkeys;
      }
      const config = state.config;
      if (!config) return;

      // 状态
      statusDot.className = 'status-dot' + (state.running ? ' running' : '');
      statusTitle.textContent = state.running ? (config.target === 'mouse' ? '正在连点…' : '正在连发…') : '空闲';
      const detail = state.running
        ? '已' + (config.target === 'mouse' ? '连点' : '连发') + ' ' + state.fired + ' 次 · 间隔 ' + state.interval
        : (config.repeatMode === 'count' ? '计划 ' + config.count + ' 次 · 间隔 ' + state.interval : '运行到手动停止 · 间隔 ' + state.interval);
      statusDetail.textContent = detail;
      toggleBtn.textContent = state.running ? '停止' : '开始';
      toggleBtn.className = 'btn' + (state.running ? ' danger' : '');

      // 热键标签
      tagRow.innerHTML = '';
      tagRow.append(
        Seraphim.el('span', { class: 'muted' }, '启停 ' + acceleratorDisplay(config.hotKey)),
        Seraphim.el('span', { class: 'muted' }, '拾取 ' + acceleratorDisplay(config.pickHotKey)));

      // 目标
      targetSelect.value = config.target;
      mouseGroup.style.display = config.target === 'mouse' ? '' : 'none';
      keyGroup.style.display = config.target === 'keyboard' ? '' : 'none';
      buttonSelect.value = config.button;
      styleSelect.value = config.clickStyle;
      setIfIdle(pressInput, config.pressMs);
      holdCheck.checked = !!config.holdKey;
      keyBtn.textContent = chordDisplay(config.key);
      pressInput.disabled = config.target === 'keyboard' && config.holdKey;

      // 位置
      positionSelect.value = config.positionMode;
      fixedGroup.style.display = config.positionMode === 'fixed' ? '' : 'none';
      setIfIdle(xInput, config.fixedX);
      setIfIdle(yInput, config.fixedY);
      moveCheck.checked = !!config.movePointer;

      // 节奏
      setIfIdle(intervalInput, config.intervalMs);
      randomCheck.checked = !!config.randomize;
      randomGroup.style.display = config.randomize ? '' : 'none';
      setIfIdle(randomMin, config.randomMinMs);
      setIfIdle(randomMax, config.randomMaxMs);
      repeatSelect.value = config.repeatMode;
      countWrap.style.display = config.repeatMode === 'count' ? '' : 'none';
      setIfIdle(countInput, config.count);

      // 热键
      toggleKeyBtn.textContent = acceleratorDisplay(config.hotKey);
      pickKeyBtn.textContent = acceleratorDisplay(config.pickHotKey);
      toggleKeyCheck.checked = !!config.hotKeyEnabled;
      pickKeyCheck.checked = !!config.pickHotKeyEnabled;
      soundCheck.checked = !!config.soundFeedback;

      // 权限
      renderPermission();

      // 错误
      if (state.lastError) stateError(state.lastError);
    }

    function renderPermission() {
      permissionBox.innerHTML = '';
      if (state.permission.granted) {
        permissionBox.append(Seraphim.el('div', { style: { color: 'var(--ok, #2e9d63)' } }, '✅ 已获得辅助功能权限'));
        return;
      }
      permissionBox.append(
        Seraphim.el('div', { class: 'err', style: { marginBottom: '8px' } },
          '还差「辅助功能」权限：向别的 App 发点击和按键必须有它。'),
        Seraphim.el('div', { class: 'btn-row', style: { marginTop: '0' } },
          Seraphim.el('button', {
            class: 'btn', onclick: async () => {
              const result = await api.requestPermission();
              render({ permission: result });
              Seraphim.toast('系统弹窗里点「打开系统设置」，勾上后再回来', true);
            }
          }, '请求授权'),
          Seraphim.el('button', {
            class: 'btn secondary', onclick: () => api.openPermissionSettings()
          }, '打开系统设置'),
          Seraphim.el('button', {
            class: 'btn secondary', onclick: async () => render({ permission: await api.permission() })
          }, '重新检查')));
    }

    function picked(position) {
      Seraphim.toast('已记录坐标 (' + position.x + ', ' + position.y + ')');
    }

    // ---------- 订阅 + 初始化 ----------
    ensureSubscription();
    activeView = { render, picked };

    (async () => {
      const [config, current] = await Promise.all([api.getConfig(), api.state()]);
      state.config = config;
      render(current);
    })();

    // 权限可能在系统设置里被改，隔一会儿对一次账
    startPermissionPolling();
  }
});

// ---------- 模块级：只订阅一次 ----------
let activeView = null;
let subscribed = false;
let permissionTimer = null;

function ensureSubscription() {
  if (subscribed) return;
  subscribed = true;
  const api = window.seraphim.autoclick;
  api.onState(next => { if (activeView) activeView.render(next); });
  api.onPicked(position => { if (activeView) activeView.picked(position); });
}

function startPermissionPolling() {
  if (permissionTimer) clearInterval(permissionTimer);
  const api = window.seraphim.autoclick;
  permissionTimer = setInterval(async () => {
    if (!activeView) return;
    const permission = await api.permission();
    activeView.render({ permission });
  }, 1500);
}
