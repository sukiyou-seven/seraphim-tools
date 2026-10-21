// Seraphim Tools — 连点引擎
//
// 纯 Node 模块：不依赖 Electron，也不直接碰屏幕 API。鼠标 / 键盘动作由调用方注入
// （主进程注入 @nut-tree-fork/nut-js，台本注入收集器），这样「什么时候该点、点几次、
// 间隔多少、按住不放怎么收尾」这些状态机可以脱离辅助功能权限单测。

'use strict';

const DEFAULT_CONFIG = {
  // 动作
  target: 'mouse',              // mouse | keyboard
  button: 'left',               // left | right | middle
  clickStyle: 'single',         // single | double
  pressMs: 30,
  positionMode: 'cursor',       // cursor | fixed
  fixedX: 0,
  fixedY: 0,
  movePointer: true,
  // 键盘
  key: { code: 'KeyA', display: 'A', modifiers: [] },
  holdKey: false,
  // 节奏
  intervalMs: 100,
  randomize: false,
  randomMinMs: 80,
  randomMaxMs: 120,
  repeatMode: 'infinite',       // infinite | count
  count: 100,
  // 热键与反馈
  hotKey: 'F6',
  pickHotKey: 'F7',
  hotKeyEnabled: true,
  pickHotKeyEnabled: true,
  soundFeedback: false
};

const MIN_INTERVAL_MS = 10;
const MAX_INTERVAL_MS = 3600000;
const MAX_PRESS_MS = 2000;
const MAX_COUNT = 10000000;

// 修饰键 → nut-js 的 Key 名（按下正序，松开逆序）
const MODIFIER_NAMES = {
  control: 'LeftControl',
  option: 'LeftAlt',
  shift: 'LeftShift',
  command: 'LeftSuper'
};
const MODIFIER_ORDER = ['control', 'option', 'shift', 'command'];

const BUTTON_NAMES = { left: 'LEFT', right: 'RIGHT', middle: 'MIDDLE' };

// DOM KeyboardEvent.code → nut-js 的 Key 枚举名
const CODE_TO_KEY = {
  Space: 'Space',
  Enter: 'Enter',
  NumpadEnter: 'Enter',
  Escape: 'Escape',
  Tab: 'Tab',
  Backspace: 'Backspace',
  Delete: 'Delete',
  Insert: 'Insert',
  Home: 'Home',
  End: 'End',
  PageUp: 'PageUp',
  PageDown: 'PageDown',
  ArrowLeft: 'Left',
  ArrowRight: 'Right',
  ArrowUp: 'Up',
  ArrowDown: 'Down',
  Minus: 'Minus',
  Equal: 'Equal',
  Comma: 'Comma',
  Period: 'Period',
  Slash: 'Slash',
  Semicolon: 'Semicolon',
  Quote: 'Quote',
  BracketLeft: 'LeftBracket',
  BracketRight: 'RightBracket',
  Backslash: 'Backslash',
  Backquote: 'Grave'
};

function clamp(value, lower, upper) {
  return Math.min(Math.max(value, lower), upper);
}

/** 空值 / 非数字回落默认值；0 是合法输入，不能被 `||` 吃掉 */
function toNumber(value, fallback) {
  if (value === undefined || value === null || value === '') return fallback;
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

/** DOM code（KeyA / Digit1 / ArrowLeft）→ nut-js Key 名；认不出返回 null */
function nutKeyName(code) {
  if (!code) return null;
  if (/^Key[A-Z]$/.test(code)) return code.slice(3);
  if (/^Digit\d$/.test(code)) return 'Num' + code.slice(5);
  if (/^Numpad\d$/.test(code)) return 'NumPad' + code.slice(6);
  if (/^F([1-9]|1\d|20)$/.test(code)) return code;
  return CODE_TO_KEY[code] || null;
}

function normalizeConfig(input) {
  const config = Object.assign({}, DEFAULT_CONFIG, input || {});
  config.key = Object.assign({}, DEFAULT_CONFIG.key, (input && input.key) || {});

  config.pressMs = clamp(toNumber(config.pressMs, 0), 0, MAX_PRESS_MS);
  config.intervalMs = clamp(toNumber(config.intervalMs, 100), MIN_INTERVAL_MS, MAX_INTERVAL_MS);
  config.randomMinMs = clamp(toNumber(config.randomMinMs, 80), MIN_INTERVAL_MS, MAX_INTERVAL_MS);
  config.randomMaxMs = clamp(toNumber(config.randomMaxMs, 120), MIN_INTERVAL_MS, MAX_INTERVAL_MS);
  if (config.randomMinMs > config.randomMaxMs) {
    const swap = config.randomMinMs;
    config.randomMinMs = config.randomMaxMs;
    config.randomMaxMs = swap;
  }
  config.count = clamp(toNumber(config.count, 1), 1, MAX_COUNT);
  config.fixedX = toNumber(config.fixedX, 0);
  config.fixedY = toNumber(config.fixedY, 0);
  return config;
}

function nextIntervalMs(config) {
  if (!config.randomize) return config.intervalMs;
  const span = config.randomMaxMs - config.randomMinMs;
  return config.randomMinMs + Math.floor(Math.random() * (span + 1));
}

/** 人话描述间隔，状态栏用 */
function describeInterval(config) {
  if (!config.randomize) return config.intervalMs + ' 毫秒';
  return config.randomMinMs + '–' + config.randomMaxMs + ' 毫秒';
}

class AutoClickerEngine {
  /**
   * @param {object} deps
   * @param {object} deps.mouse      nut-js mouse（setPosition / getPosition / pressButton / releaseButton）
   * @param {object} deps.keyboard   nut-js keyboard（pressKey / releaseKey）
   * @param {Function} deps.Point    nut-js Point 构造器
   * @param {object} deps.Button     nut-js Button 枚举
   * @param {object} deps.Key        nut-js Key 枚举
   * @param {Function} [deps.onProgress]  (fired) => void，每次触发后调用
   * @param {Function} [deps.onFinish]    (fired) => void，次数跑完时调用
   * @param {Function} [deps.sleep]       (ms) => Promise，测试可注入即时实现
   */
  constructor(deps) {
    this.mouse = deps.mouse;
    this.keyboard = deps.keyboard;
    this.Point = deps.Point;
    this.Button = deps.Button;
    this.Key = deps.Key;
    this.onProgress = deps.onProgress || function () {};
    this.onFinish = deps.onFinish || function () {};
    this.sleep = deps.sleep || function (ms) { return new Promise(resolve => setTimeout(resolve, ms)); };

    this.timer = null;
    this.generation = 0;
    this.fired = 0;
    this.config = null;
    this.heldKeys = null;       // 按住不放时已经按下的 nut Key 名（逆序松开）
  }

  get running() {
    return this.timer !== null || this.heldKeys !== null;
  }

  start(config) {
    this.stop();
    const normalized = normalizeConfig(config);
    const check = this.validate(normalized);
    if (check) throw new Error(check);

    this.config = normalized;
    this.fired = 0;
    this.generation += 1;
    const generation = this.generation;
    this.tick(generation);
    return normalized;
  }

  stop() {
    this.generation += 1;
    if (this.timer) {
      clearTimeout(this.timer);
      this.timer = null;
    }
    this.releaseHeldKeys();
    this.config = null;
  }

  /** 启动前把「按键认不出 / 按钮不存在」这类错误拦下来，别让它静默空转 */
  validate(config) {
    if (config.target === 'keyboard') {
      const name = nutKeyName(config.key.code);
      if (!name) return '不支持的按键：' + (config.key.code || '未设置');
      if (this.Key && this.Key[name] === undefined) return '这个按键 nut-js 不认：' + name;
    } else if (this.Button && this.Button[BUTTON_NAMES[config.button]] === undefined) {
      return '不支持的鼠标按键：' + config.button;
    }
    return null;
  }

  async tick(generation) {
    if (generation !== this.generation || !this.config) return;
    const config = this.config;
    const started = Date.now();

    try {
      await this.fire(config);
    } catch (error) {
      // 单次失败不打死整个循环（权限被撤销时也走这里）
      this.lastError = error && error.message ? error.message : String(error);
    }
    if (generation !== this.generation) return;

    this.fired += 1;
    this.onProgress(this.fired);

    if (config.repeatMode === 'count' && this.fired >= Math.max(1, config.count)) {
      this.stop();
      this.onFinish(this.fired);
      return;
    }

    if (config.target === 'keyboard' && config.holdKey) {
      // 已经按住了，不再发事件；等 stop() 来松手
      this.timer = null;
      return;
    }

    const interval = nextIntervalMs(config);
    const elapsed = Date.now() - started;
    this.timer = setTimeout(() => this.tick(generation), Math.max(0, interval - elapsed));
  }

  async fire(config) {
    if (config.target === 'mouse') return this.fireMouse(config);
    return this.fireKey(config);
  }

  async fireMouse(config) {
    const buttonName = BUTTON_NAMES[config.button] || 'LEFT';
    const button = this.Button[buttonName];

    if (config.positionMode === 'fixed' && config.movePointer) {
      await this.mouse.setPosition(new this.Point(config.fixedX, config.fixedY));
    }

    const rounds = config.clickStyle === 'double' ? 2 : 1;
    for (let round = 0; round < rounds; round += 1) {
      await this.mouse.pressButton(button);
      if (config.pressMs > 0) await this.sleep(config.pressMs);
      await this.mouse.releaseButton(button);
      // 双击的两下之间留一点缝，太紧会被系统合并成一下
      if (round + 1 < rounds) await this.sleep(20);
    }
  }

  async fireKey(config) {
    const names = [];
    for (const modifier of MODIFIER_ORDER) {
      if ((config.key.modifiers || []).includes(modifier)) {
        names.push(MODIFIER_NAMES[modifier]);
      }
    }
    names.push(nutKeyName(config.key.code));

    const pressed = [];
    for (const name of names) {
      await this.keyboard.pressKey(this.Key[name]);
      pressed.push(name);
    }

    if (config.holdKey) {
      this.heldKeys = pressed;
      return;
    }

    if (config.pressMs > 0) await this.sleep(config.pressMs);
    for (const name of pressed.slice().reverse()) {
      await this.keyboard.releaseKey(this.Key[name]);
    }
  }

  releaseHeldKeys() {
    if (!this.heldKeys) return;
    const names = this.heldKeys;
    this.heldKeys = null;
    for (const name of names.slice().reverse()) {
      try {
        this.keyboard.releaseKey(this.Key[name]);
      } catch (error) {
        // 退出时松不开也不能拦着进程结束
      }
    }
  }
}

module.exports = {
  AutoClickerEngine,
  DEFAULT_CONFIG,
  normalizeConfig,
  nextIntervalMs,
  describeInterval,
  nutKeyName,
  MODIFIER_NAMES,
  MODIFIER_ORDER,
  BUTTON_NAMES,
  MIN_INTERVAL_MS,
  MAX_INTERVAL_MS,
  MAX_PRESS_MS
};
