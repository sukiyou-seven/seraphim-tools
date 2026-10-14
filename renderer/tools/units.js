// 单位换算：长度 / 重量 / 温度 / 数据 / 面积 / 体积 / 速度 / 时间
Seraphim.register({
  id: 'units',
  name: '单位换算',
  icon: '📐',
  category: '常用',
  desc: '长度、重量、温度、数据、面积、体积、速度、时间',

  mount(root) {
    const FACTORS = {
      '长度': { '毫米': .001, '厘米': .01, '米': 1, '千米': 1000, '英寸': .0254, '英尺': .3048, '码': .9144, '英里': 1609.344, '海里': 1852, '寸(市)': 0.0333333, '尺(市)': 0.333333, '里(市)': 500 },
      '重量': { '毫克': 1e-6, '克': .001, '千克': 1, '吨': 1000, '盎司': .0283495, '磅': .453592, '斤(市)': .5, '两(市)': .05, '克拉': .0002 },
      '温度': null, // 特殊公式
      '数据': { 'bit': 1/8, 'B': 1, 'KB': 1024, 'MB': 1024**2, 'GB': 1024**3, 'TB': 1024**4, 'PB': 1024**5, 'Kb': 125, 'Mb': 125000, 'Gb': 125000000 },
      '面积': { '平方毫米': 1e-6, '平方厘米': 1e-4, '平方米': 1, '平方千米': 1e6, '公顷': 1e4, '亩(市)': 666.6667, '平方英尺': .092903, '平方英里': 2589988, '英亩': 4046.86 },
      '体积': { '毫升': .001, '升': 1, '立方米': 1000, '加仑(美)': 3.78541, '加仑(英)': 4.54609, '杯': .24, '汤匙': .0147868, '茶匙': .00492892, '桶(油)': 158.987 },
      '速度': { '米/秒': 1, '千米/时': 1/3.6, '英里/时': .44704, '节': .514444, '英尺/秒': .3048, '马赫': 340.29 },
      '时间': { '毫秒': .001, '秒': 1, '分钟': 60, '小时': 3600, '天': 86400, '周': 604800, '月(30天)': 2592000, '年(365天)': 31536000 }
    };

    const cats = Object.keys(FACTORS);
    let cat = Seraphim.store.get('units.cat', '长度');
    if (!cats.includes(cat)) cat = '长度';

    const catChips = Seraphim.el('div', { class: 'card' });
    const panel = Seraphim.el('div');

    function renderChips() {
      catChips.innerHTML = '';
      for (const c of cats) {
        catChips.append(Seraphim.el('span', {
          class: 'chip' + (c === cat ? ' on' : ''),
          onclick: () => { cat = c; Seraphim.store.set('units.cat', cat); renderChips(); renderPanel(); }
        }, c));
      }
    }

    function renderPanel() {
      panel.innerHTML = '';
      const units = Object.keys(FACTORS[cat] || ['°C', '°F', 'K']);
      const value = Seraphim.el('input', { type: 'text', placeholder: '输入数值' });
      value.value = Seraphim.store.get('units.value.' + cat, '1');
      const from = Seraphim.el('select', {}, ...units.map(u => Seraphim.el('option', { value: u }, u)));
      from.value = Seraphim.store.get('units.from.' + cat, units[2] || units[0]);
      const out = Seraphim.el('div', { class: 'out' });

      function convert() {
        Seraphim.store.set('units.value.' + cat, value.value);
        Seraphim.store.set('units.from.' + cat, from.value);
        const v = parseFloat(value.value);
        if (Number.isNaN(v)) { out.textContent = '请输入合法数值'; return; }
        const lines = [];
        if (cat === '温度') {
          const toC = from.value === '°C' ? v : from.value === '°F' ? (v - 32) * 5 / 9 : v - 273.15;
          for (const u of units) {
            const r = u === '°C' ? toC : u === '°F' ? toC * 9 / 5 + 32 : toC + 273.15;
            lines.push(`${u.padEnd(4)} ${Number(r.toFixed(4))}`);
          }
        } else {
          const base = v * FACTORS[cat][from.value];
          for (const [u, f] of Object.entries(FACTORS[cat])) {
            if (u === from.value) continue;
            const r = base / f;
            lines.push(`${u.padEnd(8)} ${Number(r.toPrecision(10))}`);
          }
        }
        out.textContent = lines.join('\n');
      }
      value.addEventListener('input', Seraphim.debounce(convert, 200));
      from.addEventListener('change', convert);
      convert();

      panel.append(Seraphim.el('div', { class: 'card' },
        Seraphim.el('h3', {}, `${cat}换算`),
        Seraphim.el('label', { class: 'fld' }, '数值'),
        value,
        Seraphim.el('label', { class: 'fld' }, '源单位'),
        from,
        Seraphim.el('div', { class: 'btn-row' },
          Seraphim.el('button', { class: 'btn secondary', onclick: () => Seraphim.copy(out.textContent, '换算结果已复制') }, '复制全部')),
        out));
    }

    renderChips(); renderPanel();
    root.append(catChips, panel);
  }
});
