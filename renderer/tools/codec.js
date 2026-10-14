// 编码解码：Base64 / URL / Unicode / HTML 实体 / Hex / JWT
Seraphim.register({
  id: 'codec',
  name: '编码解码',
  icon: '🔁',
  category: '常用',
  desc: 'Base64、URL、Unicode 转义、HTML 实体、Hex、JWT 解码',

  mount(root) {
    const b64Encode = s => btoa(String.fromCharCode(...new TextEncoder().encode(s)));
    const b64Decode = s => new TextDecoder().decode(Uint8Array.from(atob(s.trim()), c => c.charCodeAt(0)));
    const hexEncode = s => [...new TextEncoder().encode(s)].map(b => b.toString(16).padStart(2, '0')).join('');
    const hexDecode = h => new TextDecoder().decode(
      new Uint8Array((h.trim().replace(/\s+/g, '').match(/.{2}/g) || []).map(x => parseInt(x, 16))));

    const MODES = [
      { key: 'b64', label: 'Base64', encode: s => b64Encode(s),
        decode: s => { const t = b64Decode(s); if (!t) throw new Error('解码结果为空'); return t; } },
      { key: 'url', label: 'URL', encode: s => encodeURIComponent(s),
        decode: s => decodeURIComponent(s.replace(/\+/g, '%20')) },
      { key: 'unicode', label: 'Unicode 转义',
        encode: s => [...s].map(c => c.codePointAt(0) > 127
          ? '\\u' + c.codePointAt(0).toString(16).padStart(4, '0') : c).join(''),
        decode: s => s.replace(/\\u\{([0-9a-fA-F]+)\}|\\u([0-9a-fA-F]{4})/g,
          (_, br, u) => String.fromCodePoint(parseInt(br || u, 16))) },
      { key: 'html', label: 'HTML 实体',
        encode: s => s.replace(/[&<>"']/g, c =>
          ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])),
        decode: s => { const d = document.createElement('textarea'); d.innerHTML = s; return d.value; } },
      { key: 'hex', label: 'Hex', encode: s => hexEncode(s), decode: s => hexDecode(s) }
    ];

    const card = Seraphim.el('div', { class: 'card' });
    let mode = Seraphim.store.get('codec.mode', 'b64');
    let dir = Seraphim.store.get('codec.dir', 'encode');

    const chips = Seraphim.el('div');
    const dirChips = Seraphim.el('div', { class: 'btn-row', style: { marginTop: '4px' } });
    const input = Seraphim.el('textarea', { placeholder: '输入内容' });
    const output = Seraphim.el('div', { class: 'out empty' }, '结果');

    function renderChips() {
      chips.innerHTML = ''; dirChips.innerHTML = '';
      for (const m of MODES) {
        chips.append(Seraphim.el('span', {
          class: 'chip' + (m.key === mode ? ' on' : ''),
          onclick: () => { mode = m.key; Seraphim.store.set('codec.mode', mode); renderChips(); run(); }
        }, m.label));
      }
      dirChips.append(
        Seraphim.el('button', {
          class: 'btn' + (dir === 'encode' ? '' : ' secondary'),
          onclick: () => { dir = 'encode'; Seraphim.store.set('codec.dir', dir); renderChips(); run(); }
        }, '编码 →'),
        Seraphim.el('button', {
          class: 'btn' + (dir === 'decode' ? '' : ' secondary'),
          onclick: () => { dir = 'decode'; Seraphim.store.set('codec.dir', dir); renderChips(); run(); }
        }, '← 解码'));
    }

    function run() {
      const m = MODES.find(x => x.key === mode);
      input.placeholder = dir === 'encode' ? `输入明文，进行 ${m.label} 编码` : `输入 ${m.label} 内容，还原明文`;
      const text = input.value;
      Seraphim.store.set('codec.input', text);
      if (!text.trim()) { output.className = 'out empty'; output.textContent = '结果'; return; }
      try {
        output.className = 'out';
        output.textContent = dir === 'encode' ? m.encode(text) : m.decode(text);
      } catch (e) {
        output.className = 'out err';
        output.textContent = '失败：' + e.message;
      }
    }
    input.value = Seraphim.store.get('codec.input', '');
    input.addEventListener('input', Seraphim.debounce(run, 200));
    renderChips(); run();

    card.append(
      Seraphim.el('h3', {}, '通用编解码'),
      chips, dirChips,
      Seraphim.el('label', { class: 'fld' }, '输入'),
      input,
      Seraphim.el('div', { class: 'btn-row' },
        Seraphim.el('button', { class: 'btn secondary', onclick: () => Seraphim.copy(output.textContent) }, '复制结果'),
        Seraphim.el('button', { class: 'btn secondary', onclick: () => { input.value = output.textContent; run(); } }, '结果→输入')),
      output);

    // ---- JWT 解码 ----
    const jwtIn = Seraphim.el('textarea', { placeholder: '粘贴 JWT（eyJ…）' });
    const jwtOut = Seraphim.el('div', { class: 'out empty' }, 'Header / Payload');
    function decodeJWT() {
      const t = jwtIn.value.trim();
      if (!t) { jwtOut.className = 'out empty'; jwtOut.textContent = 'Header / Payload'; return; }
      const parts = t.split('.');
      if (parts.length < 2) { jwtOut.className = 'out err'; jwtOut.textContent = '不是合法的 JWT（至少两段）'; return; }
      try {
        const h = JSON.parse(b64Decode(parts[0]));
        const p = JSON.parse(b64Decode(parts[1]));
        const fmt = o => JSON.stringify(o, null, 2);
        let extra = '';
        if (p.exp) {
          const d = new Date(p.exp * 1000);
          extra = `\n\nexp → ${d.toLocaleString()}（${d < new Date() ? '已过期' : '有效'}）`;
        }
        jwtOut.className = 'out';
        jwtOut.textContent = `—— Header ——\n${fmt(h)}\n\n—— Payload ——\n${fmt(p)}${extra}`;
      } catch (e) {
        jwtOut.className = 'out err';
        jwtOut.textContent = '解析失败：' + e.message;
      }
    }
    jwtIn.addEventListener('input', Seraphim.debounce(decodeJWT, 250));

    root.append(Seraphim.el('div', { class: 'grid2' }, card,
      Seraphim.el('div', { class: 'card' },
        Seraphim.el('h3', {}, 'JWT 解码（不验签）'),
        jwtIn, jwtOut)));
  }
});
