// 屏幕取色：desktopCapturer 截屏 + 画布点选（Electron 专属）
Seraphim.register({
  id: 'picker',
  name: '屏幕取色',
  icon: '🎨',
  category: '桌面',
  desc: '截取屏幕画面点选取色，历史色一键复制',

  mount(root) {
    const status = Seraphim.el('div', { class: 'muted' }, '点击「截取屏幕」开始');
    const canvas = Seraphim.el('canvas', { id: 'pick-canvas', width: 1200, height: 675 });
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    const colorLabel = Seraphim.el('div', { class: 'out empty' }, '把鼠标移到画面上取色，点击记录');
    const dot = Seraphim.el('span', {
      class: 'swatch-dot',
      style: { width: '22px', height: '22px', display: 'inline-block', background: '#ccc' }
    });
    const history = Seraphim.store.get('picker.history', []);

    const histBox = Seraphim.el('div', { style: { marginTop: '10px' } });
    function renderHistory() {
      histBox.innerHTML = '';
      if (!history.length) {
        histBox.append(Seraphim.el('span', { class: 'muted' }, '暂无历史'));
        return;
      }
      for (const hex of [...history].reverse().slice(0, 24)) {
        histBox.append(Seraphim.el('span', {
          class: 'swatch',
          onclick: () => Seraphim.copy(hex, hex + ' 已复制')
        },
          Seraphim.el('span', { class: 'swatch-dot', style: { background: hex } }), hex));
      }
      histBox.append(Seraphim.el('button', {
        class: 'btn secondary', style: { marginLeft: '8px' },
        onclick: () => { Seraphim.store.set('picker.history', []); history.length = 0; renderHistory(); }
      }, '清空'));
    }
    renderHistory();

    async function capture() {
      status.textContent = '正在截取屏幕…';
      try {
        const dataURL = await window.seraphim.screenThumbnail(1440);
        const img = new Image();
        img.onload = () => {
          canvas.width = img.naturalWidth;
          canvas.height = img.naturalHeight;
          ctx.drawImage(img, 0, 0);
          status.textContent = '在画面上移动取色，点击记录颜色（截图为截取瞬间画面）';
        };
        img.src = dataURL;
      } catch (e) {
        status.textContent = '截屏失败：' + e.message;
      }
    }

    function pickAt(e, commit) {
      const rect = canvas.getBoundingClientRect();
      const x = Math.round((e.clientX - rect.left) * canvas.width / rect.width);
      const y = Math.round((e.clientY - rect.top) * canvas.height / rect.height);
      const d = ctx.getImageData(x, y, 1, 1).data;
      const hex = '#' + [d[0], d[1], d[2]].map(v => v.toString(16).padStart(2, '0')).join('').toUpperCase();
      dot.style.background = hex;
      colorLabel.className = 'out';
      colorLabel.textContent = `${hex}   rgb(${d[0]}, ${d[1]}, ${d[2]})`;
      if (commit) {
        if (!history.includes(hex)) history.push(hex);
        Seraphim.store.set('picker.history', history.slice(-48));
        renderHistory();
        Seraphim.copy(hex, hex + ' 已复制并记录');
      }
    }
    canvas.addEventListener('mousemove', e => pickAt(e, false));
    canvas.addEventListener('click', e => pickAt(e, true));

    root.append(
      Seraphim.el('div', { class: 'card' },
        Seraphim.el('h3', {}, '取色'),
        Seraphim.el('div', { class: 'btn-row', style: { marginTop: '0' } },
          Seraphim.el('button', { class: 'btn', onclick: capture }, '📸 截取屏幕'),
          Seraphim.el('button', {
            class: 'btn secondary',
            onclick: () => Seraphim.copy((colorLabel.textContent.match(/#[0-9A-F]+/) || [''])[0], '已复制当前颜色')
          }, '复制当前色')),
        Seraphim.el('div', { style: { marginTop: '10px' } }, status),
        Seraphim.el('div', { style: { marginTop: '10px' } }, canvas),
        Seraphim.el('div', { style: { marginTop: '10px', display: 'flex', alignItems: 'center', gap: '10px' } }, dot, colorLabel)),
      Seraphim.el('div', { class: 'card' },
        Seraphim.el('h3', {}, '历史颜色'),
        histBox));
  }
});
