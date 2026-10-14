// 开发辅助：JSON 格式化 / 正则测试 / 时间戳
Seraphim.register({
  id: 'devkit',
  name: '开发辅助',
  icon: '🧰',
  category: '开发',
  desc: 'JSON 格式化校验、正则测试、时间戳双向转换',

  mount(root) {
    const grid = Seraphim.el('div', { class: 'grid2' });

    // ---- JSON ----
    const jsonIn = Seraphim.el('textarea', { style: { minHeight: '150px' }, placeholder: '粘贴 JSON' });
    const jsonOut = Seraphim.el('div', { class: 'out empty' }, '格式化结果 / 校验信息');
    function fmtJSON(compact) {
      const t = jsonIn.value.trim();
      if (!t) return;
      try {
        const obj = JSON.parse(t);
        jsonOut.className = 'out';
        jsonOut.textContent = compact ? JSON.stringify(obj) : JSON.stringify(obj, null, 2);
      } catch (e) {
        jsonOut.className = 'out err';
        jsonOut.textContent = 'JSON 无效：' + e.message;
      }
    }
    jsonIn.addEventListener('input', Seraphim.debounce(() => fmtJSON(false), 400));
    const jsonCard = Seraphim.el('div', { class: 'card' },
      Seraphim.el('h3', {}, 'JSON 格式化'),
      jsonIn,
      Seraphim.el('div', { class: 'btn-row' },
        Seraphim.el('button', { class: 'btn', onclick: () => fmtJSON(false) }, '美化'),
        Seraphim.el('button', { class: 'btn', onclick: () => fmtJSON(true) }, '压缩'),
        Seraphim.el('button', { class: 'btn secondary', onclick: () => Seraphim.copy(jsonOut.textContent) }, '复制')),
      jsonOut);
    grid.append(jsonCard);

    // ---- 正则 ----
    const rePattern = Seraphim.el('input', { type: 'text', placeholder: '正则表达式，如 (\\d{4})-(\\d{2})' });
    const reFlags = Seraphim.el('input', { type: 'text', value: 'g', placeholder: '标志 g i m s u y' });
    const reText = Seraphim.el('textarea', { placeholder: '测试文本' });
    const reOut = Seraphim.el('div', { class: 'out empty' }, '匹配结果');
    const reHl = Seraphim.el('div', { class: 'out', style: { maxHeight: '160px' } });

    function testRegex() {
      const p = rePattern.value, f = reFlags.value.replace(/[^gimsuy]/g, '');
      const text = reText.value;
      reHl.innerHTML = ''; reOut.innerHTML = '';
      if (!p || !text) { reOut.className = 'out empty'; reOut.textContent = '匹配结果'; return; }
      try {
        const re = new RegExp(p, f.includes('g') ? f : f + 'g');
        const matches = [...text.matchAll(re)];
        if (!matches.length) {
          reOut.className = 'out'; reOut.textContent = '（无匹配）'; reHl.textContent = text;
          return;
        }
        // 高亮
        let html = '', last = 0;
        for (const m of matches) {
          html += escapeHtml(text.slice(last, m.index))
            + '<span class="re-hl">' + escapeHtml(m[0]) + '</span>';
          last = m.index + m[0].length;
          if (m[0] === '') break; // 空匹配保护
        }
        html += escapeHtml(text.slice(last));
        reHl.innerHTML = html;
        // 明细
        const lines = matches.slice(0, 200).map((m, i) =>
          `#${i + 1} [${m.index}] ${JSON.stringify(m[0])}` +
          (m.length > 1 ? `  分组: ${m.slice(1).map(g => JSON.stringify(g)).join(', ')}` : ''));
        reOut.className = 'out';
        reOut.textContent = `${matches.length} 处匹配\n` + lines.join('\n');
      } catch (e) {
        reOut.className = 'out err';
        reOut.textContent = '正则错误：' + e.message;
      }
    }
    const escapeHtml = s => s.replace(/[&<>"]/g, c =>
      ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
    rePattern.addEventListener('input', Seraphim.debounce(testRegex, 250));
    reFlags.addEventListener('input', Seraphim.debounce(testRegex, 250));
    reText.addEventListener('input', Seraphim.debounce(testRegex, 250));

    grid.append(Seraphim.el('div', { class: 'card' },
      Seraphim.el('h3', {}, '正则测试'),
      Seraphim.el('label', { class: 'fld' }, '表达式'),
      rePattern,
      Seraphim.el('label', { class: 'fld' }, '标志'),
      reFlags,
      Seraphim.el('label', { class: 'fld' }, '测试文本'),
      reText,
      Seraphim.el('div', { class: 'muted', style: { marginTop: '6px' } }, '高亮预览'),
      reHl, reOut));

    // ---- 时间戳 ----
    const tsNow = () => Math.floor(Date.now() / 1000);
    const tsIn = Seraphim.el('input', { type: 'text', placeholder: '秒或毫秒时间戳（10/13 位）' });
    const tsOut = Seraphim.el('div', { class: 'out empty' }, '对应时间');
    function tsConvert() {
      const t = tsIn.value.trim();
      if (!t) { tsOut.className = 'out empty'; tsOut.textContent = '对应时间'; return; }
      const n = Number(t);
      if (!Number.isFinite(n)) { tsOut.className = 'out err'; tsOut.textContent = '不是数字'; return; }
      const ms = String(Math.abs(Math.trunc(n))).length > 11 ? n : n * 1000;
      const d = new Date(ms);
      if (Number.isNaN(d.getTime())) { tsOut.className = 'out err'; tsOut.textContent = '超出日期范围'; return; }
      tsOut.className = 'out';
      tsOut.textContent = [
        `本地: ${d.toLocaleString()}`,
        `UTC : ${d.toUTCString()}`,
        `ISO : ${d.toISOString()}`
      ].join('\n');
    }
    tsIn.addEventListener('input', Seraphim.debounce(tsConvert, 200));

    const dateIn = Seraphim.el('input', { type: 'text', placeholder: '2026-10-15 08:30:00' });
    const dateOut = Seraphim.el('div', { class: 'out empty' }, '对应时间戳');
    function dateConvert() {
      const t = dateIn.value.trim();
      if (!t) { dateOut.className = 'out empty'; dateOut.textContent = '对应时间戳'; return; }
      const d = new Date(t.replace(' ', 'T'));
      if (Number.isNaN(d.getTime())) { dateOut.className = 'out err'; dateOut.textContent = '无法解析日期'; return; }
      dateOut.className = 'out';
      dateOut.textContent = `秒: ${Math.floor(d.getTime() / 1000)}\n毫秒: ${d.getTime()}`;
    }
    dateIn.addEventListener('input', Seraphim.debounce(dateConvert, 200));

    const tsCard = Seraphim.el('div', { class: 'card' },
      Seraphim.el('h3', {}, '时间戳'),
      Seraphim.el('label', { class: 'fld' }, `时间戳 → 日期（当前 ${tsNow()}）`),
      tsIn, tsOut,
      Seraphim.el('label', { class: 'fld' }, '日期 → 时间戳'),
      dateIn, dateOut,
      Seraphim.el('div', { class: 'btn-row' },
        Seraphim.el('button', {
          class: 'btn secondary',
          onclick: () => { tsIn.value = String(tsNow()); tsConvert(); }
        }, '填入当前时间戳')),
      Seraphim.el('div', { class: 'muted', style: { marginTop: '8px' } }, '提示：时间戳工具会自动识别 10 位（秒）/ 13 位（毫秒）'));
    grid.append(tsCard);

    root.append(grid);
  }
});
