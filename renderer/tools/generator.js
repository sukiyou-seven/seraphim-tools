// 生成器：UUID v4/v7、随机密码、随机字符串
Seraphim.register({
  id: 'generator',
  name: '生成器',
  icon: '🎲',
  category: '常用',
  desc: 'UUID、随机密码、随机字符串，批量生成一键复制',

  mount(root) {
    const grid = Seraphim.el('div', { class: 'grid2' });
    const rnd = (n) => crypto.getRandomValues(new Uint8Array(n));
    const uuidv4 = () => {
      const b = rnd(16);
      b[6] = (b[6] & 0x0f) | 0x40; b[8] = (b[8] & 0x3f) | 0x80;
      const h = [...b].map(x => x.toString(16).padStart(2, '0')).join('');
      return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
    };
    const uuidv7 = () => {
      const ts = Date.now();
      const b = rnd(16);
      b[0] = (ts / 2 ** 40) & 0xff; b[1] = (ts / 2 ** 32) & 0xff;
      b[2] = (ts / 2 ** 24) & 0xff; b[3] = (ts / 2 ** 16) & 0xff;
      b[4] = (ts / 2 ** 8) & 0xff; b[5] = ts & 0xff;
      b[6] = (b[6] & 0x0f) | 0x70; b[8] = (b[8] & 0x3f) | 0x80;
      const h = [...b].map(x => x.toString(16).padStart(2, '0')).join('');
      return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
    };

    // ---- UUID ----
    const uuidCount = Seraphim.el('input', { type: 'number', min: 1, max: 500, value: 5 });
    const uuidOut = Seraphim.el('div', { class: 'out empty' }, '点「生成」产出');
    function genUUID(kind) {
      const n = Math.min(500, Math.max(1, Number(uuidCount.value) || 1));
      const list = Array.from({ length: n }, () => (kind === 'v7' ? uuidv7() : uuidv4()));
      uuidOut.className = 'out';
      uuidOut.textContent = list.join('\n');
      Seraphim.store.set('gen.uuidLast', list);
    }
    const uuidCard = Seraphim.el('div', { class: 'card' },
      Seraphim.el('h3', {}, 'UUID'),
      Seraphim.el('label', { class: 'fld' }, '数量（1~500）'),
      uuidCount,
      Seraphim.el('div', { class: 'btn-row' },
        Seraphim.el('button', { class: 'btn', onclick: () => genUUID('v4') }, 'UUID v4'),
        Seraphim.el('button', { class: 'btn', onclick: () => genUUID('v7') }, 'UUID v7（时间有序）'),
        Seraphim.el('button', { class: 'btn secondary', onclick: () => Seraphim.copy(uuidOut.textContent) }, '复制')),
      uuidOut);
    grid.append(uuidCard);

    // ---- 密码 ----
    const pwLen = Seraphim.el('input', { type: 'number', min: 4, max: 128, value: Seraphim.store.get('gen.pwLen', 16) });
    const pwSets = [
      ['upper', 'A-Z', true], ['lower', 'a-z', true], ['digit', '0-9', true],
      ['symbol', '!@#$%', true], ['similar', '排除易混淆 0O1lI', false]
    ];
    const setStates = Object.fromEntries(pwSets.map(([k, , d]) => [k, Seraphim.store.get('gen.set.' + k, d)]));
    const pwChips = Seraphim.el('div');
    function renderPwChips() {
      pwChips.innerHTML = '';
      for (const [k, label] of pwSets) {
        pwChips.append(Seraphim.el('span', {
          class: 'chip' + (setStates[k] ? ' on' : ''),
          onclick: () => { setStates[k] = !setStates[k]; Seraphim.store.set('gen.set.' + k, setStates[k]); renderPwChips(); }
        }, label));
      }
    }
    renderPwChips();
    const pwOut = Seraphim.el('div', { class: 'out empty' }, '点「生成密码」产出');

    function genPassword() {
      let pool = '';
      if (setStates.upper) pool += 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
      if (setStates.lower) pool += 'abcdefghijklmnopqrstuvwxyz';
      if (setStates.digit) pool += '0123456789';
      if (setStates.symbol) pool += '!@#$%^&*()-_=+[]{};:,.<>?';
      if (setStates.similar) pool = pool.replace(/[0O1lI|]/g, '');
      const len = Math.min(128, Math.max(4, Number(pwLen.value) || 16));
      Seraphim.store.set('gen.pwLen', len);
      if (!pool) return Seraphim.toast('至少选择一个字符集', true);
      // 防取模偏差： rejection sampling
      const rand = (max) => {
        const lim = 256 - (256 % max); let x;
        do { x = rnd(1)[0]; } while (x >= lim);
        return x % max;
      };
      const pw = Array.from({ length: len }, () => pool[rand(pool.length)]).join('');
      pwOut.className = 'out';
      pwOut.textContent = pw;
    }
    const pwCard = Seraphim.el('div', { class: 'card' },
      Seraphim.el('h3', {}, '随机密码'),
      Seraphim.el('label', { class: 'fld' }, '长度（4~128）'),
      pwLen,
      Seraphim.el('label', { class: 'fld' }, '字符集（点击切换）'),
      pwChips,
      Seraphim.el('div', { class: 'btn-row' },
        Seraphim.el('button', { class: 'btn', onclick: genPassword }, '生成密码'),
        Seraphim.el('button', { class: 'btn secondary', onclick: () => Seraphim.copy(pwOut.textContent) }, '复制')),
      pwOut);
    grid.append(pwCard);

    // ---- 随机字符串 ----
    const strLen = Seraphim.el('input', { type: 'number', min: 1, max: 4096, value: 32 });
    const strOut = Seraphim.el('div', { class: 'out empty' }, '点「生成」产出');
    const strCard = Seraphim.el('div', { class: 'card' },
      Seraphim.el('h3', {}, '随机字符串（小写+数字）'),
      Seraphim.el('label', { class: 'fld' }, '长度'),
      strLen,
      Seraphim.el('div', { class: 'btn-row' },
        Seraphim.el('button', {
          class: 'btn',
          onclick: () => {
            const pool = 'abcdefghijklmnopqrstuvwxyz0123456789';
            strOut.className = 'out';
            strOut.textContent = Array.from({ length: Number(strLen.value) || 32 },
              () => pool[crypto.getRandomValues(new Uint8Array(1))[0] % pool.length]).join('');
          }
        }, '生成'),
        Seraphim.el('button', { class: 'btn secondary', onclick: () => Seraphim.copy(strOut.textContent) }, '复制')),
      strOut);

    root.append(grid, strCard);
  }
});
