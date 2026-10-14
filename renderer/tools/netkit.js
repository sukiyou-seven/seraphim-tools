// 网络工具：本机网卡 / 公网出口 IP / HTTP 请求测试（主进程发起，无 CORS）
Seraphim.register({
  id: 'netkit',
  name: '网络工具',
  icon: '🌐',
  category: '开发',
  desc: '本机网卡、公网出口 IP、HTTP 请求测试（状态/耗时/响应头/响应体）',

  mount(root) {
    // ---- 本机 & 公网 IP ----
    const ipCard = Seraphim.el('div', { class: 'card' },
      Seraphim.el('h3', {}, 'IP 信息'),
      Seraphim.el('div', { class: 'muted' }, '加载中…'));
    (async () => {
      const lines = [];
      try {
        const ifs = await window.seraphim.netInterfaces();
        const real = ifs.filter(i => !i.internal);
        const ipv4 = real.filter(i => i.family === 'IPv4');
        const ipv6 = real.filter(i => i.family === 'IPv6');
        if (ipv4.length) lines.push('本机 IPv4\n' + ipv4.map(i => `  ${i.address}  (${i.name})`).join('\n'));
        if (ipv6.length) lines.push('本机 IPv6\n' + ipv6.slice(0, 4).map(i => `  ${i.address}  (${i.name})`).join('\n'));
        const lo = ifs.find(i => i.internal);
        if (lo) lines.push(`回环  ${lo.address}`);
      } catch { lines.push('本机网卡信息获取失败'); }

      try {
        const pub = await window.seraphim.publicIP();
        lines.push(`公网出口  ${pub.ip}（${pub.country || '?'} ${pub.city || ''} · ${new URL(pub.source).host}）`);
      } catch (e) {
        lines.push('公网出口查询失败（可能离线或被墙）：' + e.message);
      }
      ipCard.querySelector('.muted').textContent = '';
      ipCard.append(Seraphim.el('div', { class: 'out' }, lines.join('\n\n')));
    })();

    // ---- HTTP 请求测试 ----
    const urlIn = Seraphim.el('input', { type: 'text', placeholder: 'https://api.example.com/path' });
    urlIn.value = Seraphim.store.get('net.url', '');
    const methodSel = Seraphim.el('select', {},
      ...['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD'].map(m => Seraphim.el('option', { value: m }, m)));
    methodSel.value = Seraphim.store.get('net.method', 'GET');
    const hdrIn = Seraphim.el('textarea', { style: { minHeight: '64px' }, placeholder: '请求头，一行一个：\nContent-Type: application/json' });
    hdrIn.value = Seraphim.store.get('net.headers', '');
    const bodyIn = Seraphim.el('textarea', { placeholder: '请求体（POST/PUT/PATCH 时发送）' });
    bodyIn.value = Seraphim.store.get('net.body', '');
    const httpOut = Seraphim.el('div', { class: 'out empty' }, '响应');

    async function send() {
      const url = urlIn.value.trim();
      if (!/^https?:\/\//.test(url)) return Seraphim.toast('URL 需要 http(s):// 开头', true);
      Seraphim.store.set('net.url', url);
      Seraphim.store.set('net.method', methodSel.value);
      Seraphim.store.set('net.headers', hdrIn.value);
      Seraphim.store.set('net.body', bodyIn.value);

      const headers = {};
      for (const line of hdrIn.value.split('\n')) {
        const idx = line.indexOf(':');
        if (idx > 0) headers[line.slice(0, idx).trim()] = line.slice(idx + 1).trim();
      }
      httpOut.className = 'out';
      httpOut.textContent = '请求中…';
      const res = await window.seraphim.http({
        url, method: methodSel.value, headers,
        body: ['GET', 'HEAD'].includes(methodSel.value) ? null : bodyIn.value
      });
      if (res.error) {
        httpOut.className = 'out err';
        httpOut.textContent = `✗ ${res.error}（${res.ms}ms）`;
        return;
      }
      let body = res.body;
      try { body = JSON.stringify(JSON.parse(res.body), null, 2); } catch { /* 保持原文 */ }
      httpOut.textContent =
        `${res.ok ? '✓' : '✗'} ${res.status} ${res.statusText} · ${res.ms}ms\n\n` +
        `—— 响应头 ——\n` +
        Object.entries(res.headers).map(([k, v]) => `${k}: ${v}`).join('\n') +
        `\n\n—— 响应体 ——\n` + body;
    }

    const httpCard = Seraphim.el('div', { class: 'card' },
      Seraphim.el('h3', {}, 'HTTP 请求测试'),
      Seraphim.el('div', { class: 'row' }, urlIn,
        Seraphim.el('div', { style: { flex: '0 0 110px' } }, methodSel)),
      Seraphim.el('label', { class: 'fld' }, '请求头'),
      hdrIn,
      Seraphim.el('label', { class: 'fld' }, '请求体'),
      bodyIn,
      Seraphim.el('div', { class: 'btn-row' },
        Seraphim.el('button', { class: 'btn', onclick: send }, '发送请求'),
        Seraphim.el('button', { class: 'btn secondary', onclick: () => Seraphim.copy(httpOut.textContent) }, '复制响应')),
      httpOut);

    root.append(ipCard, httpCard);
  }
});
