// 加密解密：哈希（主进程 Node crypto）+ AES-GCM 口令加解密（WebCrypto）
Seraphim.register({
  id: 'crypto',
  name: '加密解密',
  icon: '🔐',
  category: '开发',
  desc: 'MD5 / SHA 系列 / HMAC；AES-256-GCM 口令加解密',

  mount(root) {
    const grid = Seraphim.el('div', { class: 'grid2' });

    // ---- 哈希 ----
    const hashIn = Seraphim.el('textarea', { placeholder: '输入文本，实时计算各哈希' });
    const hmacKey = Seraphim.el('input', { type: 'text', placeholder: 'HMAC 密钥（留空则算普通哈希）' });
    const hashOut = Seraphim.el('div', { class: 'out empty' }, '等待输入…');
    const ALGOS = [
      ['md5', 'MD5'], ['sha1', 'SHA-1'], ['sha256', 'SHA-256'], ['sha512', 'SHA-512']
    ];

    async function computeHash() {
      const text = hashIn.value;
      Seraphim.store.set('crypto.input', text);
      Seraphim.store.set('crypto.hmac', hmacKey.value);
      if (!text) { hashOut.className = 'out empty'; hashOut.textContent = '等待输入…'; return; }
      const key = hmacKey.value || null;
      const rows = [];
      for (const [algo, label] of ALGOS) {
        try {
          const hex = await window.seraphim.hash(algo, text, key);
          rows.push(`${label}${key ? '-HMAC' : ''}\n${hex}`);
        } catch (e) {
          rows.push(`${label}\n计算失败：${e.message}`);
        }
      }
      hashOut.className = 'out';
      hashOut.textContent = rows.join('\n\n');
    }
    hashIn.value = Seraphim.store.get('crypto.input', '');
    hmacKey.value = Seraphim.store.get('crypto.hmac', '');
    hashIn.addEventListener('input', Seraphim.debounce(computeHash, 300));
    hmacKey.addEventListener('input', Seraphim.debounce(computeHash, 300));

    const hashCard = Seraphim.el('div', { class: 'card' },
      Seraphim.el('h3', {}, '哈希 / HMAC'),
      Seraphim.el('label', { class: 'fld' }, '文本'),
      hashIn,
      Seraphim.el('label', { class: 'fld' }, 'HMAC 密钥（可选）'),
      hmacKey,
      Seraphim.el('div', { class: 'btn-row' },
        Seraphim.el('button', {
          class: 'btn secondary',
          onclick: () => Seraphim.copy(hashOut.textContent, '全部哈希已复制')
        }, '复制全部')),
      hashOut);
    grid.append(hashCard);

    // ---- AES-256-GCM 口令加解密（WebCrypto PBKDF2 派生） ----
    const MAGIC = 'SGAES1';
    const dec = new TextDecoder(), enc = new TextEncoder();
    const b64e = buf => btoa(String.fromCharCode(...new Uint8Array(buf)));
    const b64d = s => Uint8Array.from(atob(s), c => c.charCodeAt(0));

    async function deriveKey(password, salt) {
      const base = await crypto.subtle.importKey('raw', enc.encode(password), 'PBKDF2', false, ['deriveKey']);
      return crypto.subtle.deriveKey(
        { name: 'PBKDF2', salt, iterations: 150000, hash: 'SHA-256' },
        base, { name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
    }

    async function aesEncrypt() {
      const text = aesIn.value, pwd = aesPwd.value;
      if (!text || !pwd) return Seraphim.toast('明文和口令都要填', true);
      const salt = crypto.getRandomValues(new Uint8Array(16));
      const iv = crypto.getRandomValues(new Uint8Array(12));
      const key = await deriveKey(pwd, salt);
      const ct = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, enc.encode(text));
      aesOut.className = 'out';
      aesOut.textContent = MAGIC + '.' + b64e(salt) + '.' + b64e(iv) + '.' + b64e(ct);
      Seraphim.toast('加密完成');
    }

    async function aesDecrypt() {
      const text = aesIn.value.trim(), pwd = aesPwd.value;
      const parts = text.split('.');
      if (parts[0] !== MAGIC || parts.length !== 4)
        return Seraphim.toast('密文格式不对（应由本工具加密生成）', true);
      try {
        const key = await deriveKey(pwd, b64d(parts[1]));
        const pt = await crypto.subtle.decrypt(
          { name: 'AES-GCM', iv: b64d(parts[2]) }, key, b64d(parts[3]));
        aesOut.className = 'out';
        aesOut.textContent = dec.decode(pt);
        Seraphim.toast('解密成功');
      } catch {
        aesOut.className = 'out err';
        aesOut.textContent = '解密失败：口令错误或密文已损坏';
      }
    }

    const aesIn = Seraphim.el('textarea', {
      placeholder: '加密：填明文 → 点加密\n解密：把密文粘进来 → 点解密'
    });
    aesIn.value = Seraphim.store.get('crypto.aes', '');
    aesIn.addEventListener('input', Seraphim.debounce(() => Seraphim.store.set('crypto.aes', aesIn.value), 400));
    const aesPwd = Seraphim.el('input', { type: 'password', placeholder: '口令（不存储，仅本次会话使用）' });
    const aesOut = Seraphim.el('div', { class: 'out empty' }, '结果');

    grid.append(Seraphim.el('div', { class: 'card' },
      Seraphim.el('h3', {}, 'AES-256-GCM 口令加解密'),
      Seraphim.el('div', { class: 'muted' }, 'PBKDF2(150k) 派生密钥，输出格式 SGAES1.salt.iv.cipher（Base64）'),
      Seraphim.el('label', { class: 'fld' }, '明文 / 密文'),
      aesIn,
      Seraphim.el('label', { class: 'fld' }, '口令'),
      aesPwd,
      Seraphim.el('div', { class: 'btn-row' },
        Seraphim.el('button', { class: 'btn', onclick: aesEncrypt }, '🔒 加密'),
        Seraphim.el('button', { class: 'btn', onclick: aesDecrypt }, '🔓 解密'),
        Seraphim.el('button', { class: 'btn secondary', onclick: () => Seraphim.copy(aesOut.textContent) }, '复制')),
      aesOut));

    root.append(grid);
    computeHash();
  }
});
