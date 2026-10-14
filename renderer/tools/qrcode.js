// 二维码：生成（qrcode UMD）+ 解码（jsQR）
Seraphim.register({
  id: 'qrcode',
  name: '二维码',
  icon: '🔲',
  category: '常用',
  desc: '文本转二维码图片；图片 / 剪贴板反解二维码内容',

  mount(root) {
    const grid = Seraphim.el('div', { class: 'grid2' });

    // ---- 生成 ----
    const genInput = Seraphim.el('textarea', { placeholder: '输入文字 / 链接，实时生成二维码' });
    genInput.value = Seraphim.store.get('qr.text', 'https://github.com/sukiyou-seven/seraphim-tools');
    const ecSel = Seraphim.el('select', {},
      ...['L', 'M', 'Q', 'H'].map(x => Seraphim.el('option', { value: x }, `纠错 ${x}`)));
    ecSel.value = Seraphim.store.get('qr.ec', 'M');
    const sizeSel = Seraphim.el('select', {},
      ...[256, 384, 512].map(x => Seraphim.el('option', { value: x }, `${x} px`)));
    sizeSel.value = Seraphim.store.get('qr.size', 384);
    const qrImg = Seraphim.el('img', { style: { width: '240px', height: '240px', borderRadius: '8px', border: '1px solid var(--border)', display: 'block' } });
    const genOut = Seraphim.el('div', { class: 'muted' }, '输入内容后生成');

    async function regenerate() {
      const text = genInput.value.trim();
      Seraphim.store.set('qr.text', genInput.value);
      Seraphim.store.set('qr.ec', ecSel.value);
      Seraphim.store.set('qr.size', sizeSel.value);
      if (!text) { qrImg.removeAttribute('src'); genOut.textContent = '输入内容后生成'; return; }
      try {
        qrImg.src = await window.seraphim.qrcode(text, ecSel.value, sizeSel.value);
        genOut.classList.remove('err');
        genOut.textContent = `已生成（内容 ${text.length} 字符）`;
      } catch (err) {
        genOut.textContent = '生成失败：' + err.message;
        genOut.classList.add('err');
      }
    }
    genInput.addEventListener('input', Seraphim.debounce(regenerate, 300));
    ecSel.addEventListener('change', regenerate);
    sizeSel.addEventListener('change', regenerate);

    const dlBtn = Seraphim.el('button', {
      class: 'btn', onclick: () => {
        if (!qrImg.src) return Seraphim.toast('还没有二维码', true);
        const a = Seraphim.el('a', { href: qrImg.src, download: 'qrcode.png' });
        a.click();
        Seraphim.toast('已保存 qrcode.png');
      }
    }, '⬇ 下载 PNG');

    grid.append(Seraphim.el('div', { class: 'card' },
      Seraphim.el('h3', {}, '生成'),
      genInput,
      Seraphim.el('label', { class: 'fld' }, '纠错等级'),
      ecSel,
      Seraphim.el('label', { class: 'fld' }, '尺寸'),
      sizeSel,
      Seraphim.el('div', { class: 'btn-row' }, dlBtn),
      Seraphim.el('div', { style: { marginTop: '14px' } }, qrImg),
      genOut));

    // ---- 解码 ----
    const decOut = Seraphim.el('div', { class: 'out empty' }, '拖入 / 选择图片，或直接粘贴截图（⌘V）');
    const decCanvas = Seraphim.el('canvas', { style: { display: 'none' } });
    const decPreview = Seraphim.el('img', {
      style: { maxWidth: '100%', maxHeight: '200px', borderRadius: '8px', display: 'none' }
    });

    function decodeImage(img) {
      decCanvas.width = img.naturalWidth || img.width;
      decCanvas.height = img.naturalHeight || img.height;
      const ctx = decCanvas.getContext('2d', { willReadFrequently: true });
      ctx.drawImage(img, 0, 0);
      const data = ctx.getImageData(0, 0, decCanvas.width, decCanvas.height);
      const code = jsQR(data.data, decCanvas.width, decCanvas.height);
      decOut.classList.remove('err', 'empty');
      if (code) {
        decOut.textContent = code.data;
        Seraphim.copy(code.data, '解码成功，内容已复制');
      } else {
        decOut.textContent = '未在图中识别到二维码';
        decOut.classList.add('err');
      }
    }

    function decodeBlob(blob) {
      const url = URL.createObjectURL(blob);
      const img = new Image();
      img.onload = () => { decodeImage(img); decPreview.src = url; decPreview.style.display = 'block'; };
      img.onerror = () => { decOut.textContent = '图片无法解析'; decOut.classList.add('err'); };
      img.src = url;
    }

    const fileInput = Seraphim.el('input', { type: 'file', accept: 'image/*', style: { display: 'none' } });
    fileInput.addEventListener('change', () => fileInput.files[0] && decodeBlob(fileInput.files[0]));
    const dropZone = Seraphim.el('div', {
      class: 'card',
      ondragover: e => e.preventDefault(),
      ondrop: e => {
        e.preventDefault();
        const f = [...e.dataTransfer.files].find(f => f.type.startsWith('image/'));
        if (f) decodeBlob(f);
      },
      style: { cursor: 'pointer' }
    },
      Seraphim.el('h3', {}, '解码'),
      Seraphim.el('div', { class: 'btn-row', style: { marginTop: '0' } },
        Seraphim.el('button', { class: 'btn secondary', onclick: () => fileInput.click() }, '📁 选择图片'),
        Seraphim.el('button', {
          class: 'btn secondary',
          onclick: async () => {
            try {
              const items = await navigator.clipboard.read();
              for (const it of items) {
                const type = it.types.find(t => t.startsWith('image/'));
                if (type) return decodeBlob(await it.getType(type));
              }
              const text = await navigator.clipboard.readText().catch(() => '');
              decOut.classList.remove('empty');
              if (text.trim()) { decOut.textContent = '剪贴板是文本：\n' + text; }
              else { decOut.textContent = '剪贴板里没有图片'; decOut.classList.add('err'); }
            } catch { decOut.textContent = '读取剪贴板失败'; decOut.classList.add('err'); }
          }
        }, '📋 从剪贴板')),
      Seraphim.el('div', { class: 'muted', style: { marginTop: '8px' } }, '或把图片拖到这里'),
      decPreview, decCanvas, decOut);

    grid.append(dropZone);
    root.append(grid, fileInput);
    regenerate();
  }
});
