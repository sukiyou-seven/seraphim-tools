// 提示词库：分类模板浏览 + 一键复制
Seraphim.register({
  id: 'prompt',
  name: '提示词库',
  icon: '💬',
  category: 'AI 创作',
  desc: '常用 AI 提示词模板，点击即复制，支持 {{变量}} 占位替换',

  mount(root) {
    const TPL = [
      { cat: '编程', name: '代码审查', text: '请审查以下代码，从【正确性、性能、安全、可读性】四个维度给出问题清单和改进建议，按严重程度排序。只列真实问题，不要泛泛而谈。\n\n```\n{{代码}}\n```' },
      { cat: '编程', name: 'Bug 定位', text: '我遇到一个 Bug，请先列出 3 个最可能的根因假设，再为每个假设给出验证方法，最后给出修复建议。\n\n现象：{{现象描述}}\n相关代码：\n```\n{{代码}}\n```' },
      { cat: '编程', name: '单元测试生成', text: '为以下函数生成单元测试：覆盖正常路径、边界值、异常输入三类用例，使用 {{测试框架}} 风格，直接给出可运行代码。\n\n```\n{{函数代码}}\n```' },
      { cat: '编程', name: '代码解释', text: '逐段解释以下代码的作用，说明其中的关键设计决策和数据流，最后用一句话总结整体功能：\n\n```\n{{代码}}\n```' },
      { cat: '写作', name: '文章润色', text: '请润色下面的文字：保持原意，提升流畅度与专业性；不要添加原文没有的信息；修改幅度控制在必要范围。\n\n{{原文}}' },
      { cat: '写作', name: '周报生成', text: '根据以下工作要点，生成一份本周工作周报：分「已完成 / 进行中 / 下周计划 / 风险」四节，条目式，每条一句话，突出结果而非过程。\n\n要点：\n{{工作要点}}' },
      { cat: '写作', name: '摘要提炼', text: '把下面的内容提炼成摘要：先给 3 句话版本，再给 1 句话版本，保留关键数据和结论。\n\n{{内容}}' },
      { cat: '翻译', name: '地道中译英', text: '将下面的中文翻译成自然、地道的英文（不要翻译腔）。若原文有歧义，先列出你的理解再给译文。\n\n{{中文}}' },
      { cat: '翻译', name: '地道英译中', text: '将下面的英文翻译成流畅的中文，专有名词首次出现时保留英文原词。\n\n{{英文}}' },
      { cat: '通用', name: '结构化分析', text: '针对主题「{{主题}}」做结构化分析：背景 → 现状 → 关键矛盾 → 可选方案（各列优缺点）→ 推荐方案与理由。结论先行。' },
      { cat: '通用', name: '苏格拉底提问', text: '我想深入理解「{{主题}}」。请你扮演苏格拉底式导师：每次只问我一个问题，根据我的回答逐步追问，引导我自己想通，不要直接给答案。' },
      { cat: '通用', name: '反方意见', text: '这是我的观点：{{观点}}。请你站在反方立场，给出最有力的 3 条反驳，再指出我的论证中最薄弱的一环。' }
    ];

    const cats = [...new Set(TPL.map(t => t.cat))];
    let curCat = Seraphim.store.get('prompt.cat', cats[0]);
    let keyword = Seraphim.store.get('prompt.kw', '');
    let favs = Seraphim.store.get('prompt.favs', []);

    const chips = Seraphim.el('div');
    const kwIn = Seraphim.el('input', { type: 'text', placeholder: '搜索模板名 / 内容…' });
    kwIn.value = keyword;
    const listBox = Seraphim.el('div');

    function fillVars(text) {
      const m = text.match(/\{\{[^}]+\}\}/);
      if (!m) return null;
      return Seraphim.el('input', { type: 'text', placeholder: '填入 ' + m[0] + ' 的值' });
    }

    function render() {
      chips.innerHTML = '';
      for (const c of cats) {
        chips.append(Seraphim.el('span', {
          class: 'chip' + (c === curCat ? ' on' : ''),
          onclick: () => { curCat = c; Seraphim.store.set('prompt.cat', c); render(); }
        }, c));
      }
      chips.append(Seraphim.el('span', {
        class: 'chip' + (curCat === '收藏' ? ' on' : ''),
        onclick: () => { curCat = '收藏'; render(); }
      }, '★ 收藏'));

      listBox.innerHTML = '';
      const kw = keyword.trim().toLowerCase();
      const list = TPL.filter(t =>
        (curCat === '收藏' ? favs.includes(t.name) : t.cat === curCat) &&
        (!kw || t.name.toLowerCase().includes(kw) || t.text.toLowerCase().includes(kw)));

      if (!list.length) {
        listBox.append(Seraphim.el('div', { class: 'muted', style: { padding: '8px' } }, '（没有匹配的模板）'));
      }
      for (const t of list) {
        const varInput = fillVars(t.text);
        const preview = Seraphim.el('div', {
          class: 'out', style: { maxHeight: '110px', display: 'none' }
        }, t.text);
        const star = Seraphim.el('button', {
          class: 'btn secondary', style: { padding: '4px 10px' },
          onclick: () => {
            favs = favs.includes(t.name) ? favs.filter(x => x !== t.name) : [...favs, t.name];
            Seraphim.store.set('prompt.favs', favs);
            render();
          }
        }, favs.includes(t.name) ? '★' : '☆');

        const useBtn = Seraphim.el('button', {
          class: 'btn',
          onclick: () => {
            let text = t.text;
            if (varInput && varInput.value.trim()) {
              text = text.replace(/\{\{[^}]+\}\}/, varInput.value.trim());
            }
            Seraphim.copy(text, '提示词已复制');
          }
        }, '复制');

        listBox.append(Seraphim.el('div', { class: 'card', style: { marginBottom: '10px' } },
          Seraphim.el('div', { style: { display: 'flex', alignItems: 'center', gap: '8px' } },
            Seraphim.el('div', { style: { flex: 1, fontWeight: '600' } }, t.name),
            star),
          Seraphim.el('div', { class: 'muted', style: { marginTop: '4px' } },
            t.text.slice(0, 72) + (t.text.length > 72 ? '…' : '')),
          varInput ? Seraphim.el('div', { style: { marginTop: '8px' } }, varInput) : null,
          Seraphim.el('div', { class: 'btn-row', style: { marginTop: '10px' } },
            useBtn,
            Seraphim.el('button', {
              class: 'btn secondary',
              onclick: () => { preview.style.display = preview.style.display === 'none' ? 'block' : 'none'; }
            }, '查看全文')),
          preview));
      }
    }
    kwIn.addEventListener('input', Seraphim.debounce(() => {
      keyword = kwIn.value; Seraphim.store.set('prompt.kw', keyword); render();
    }, 200));
    render();

    root.append(
      Seraphim.el('div', { class: 'card' },
        Seraphim.el('h3', {}, '筛选'),
        chips,
        Seraphim.el('label', { class: 'fld' }, '搜索'),
        kwIn),
      listBox);
  }
});
