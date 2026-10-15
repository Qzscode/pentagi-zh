/* PentAGI 中文界面补丁 —— 运行时翻译层
 *
 * 为什么用运行时方案: pentAGI 前端没有任何 i18n 框架, 文案硬编码在 400+ 个
 * TSX 文件里。重建整个前端风险高、周期长; 而界面产物是从磁盘 (/opt/pentagi/fe)
 * 提供的, 所以用一个挂载进去的脚本做表层翻译, 既能立刻见效, 又能随时卸载。
 *
 * 三条安全边界:
 *   1. 绝不翻译 code/pre/textarea/终端/编辑器 内的内容 —— 那是命令与日志原文。
 *   2. 先做整串精确匹配, 再做子串替换; 未命中的一律原样保留英文。
 *   3. 自身造成的 DOM 改动会再次触发 MutationObserver, 但二次匹配必然无变化,
 *      因此收敛, 不会死循环。
 */
(function () {
    'use strict';

    var DICT = window.__PENTAGI_ZH_DICT || {};
    var ATTRS = ['placeholder', 'title', 'aria-label', 'alt'];

    // 这些容器里的文本是"技术载荷", 翻译会破坏它
    var SKIP_SELECTOR = 'script,style,code,pre,textarea,samp,kbd,.xterm,.monaco-editor,[contenteditable="true"],[data-zh-skip]';

    function hasDict() {
        for (var k in DICT) { if (Object.prototype.hasOwnProperty.call(DICT, k)) { return true; } }
        return false;
    }
    if (!hasDict()) { return; }

    // ---------------------------------------------------------------- 匹配器
    function escapeRe(s) { return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); }

    var keys = Object.keys(DICT).filter(function (k) { return k.length >= 2; });
    // 长键优先, 否则 "Upload" 会先于 "Upload files" 命中
    keys.sort(function (a, b) { return b.length - a.length; });

    // 短键只允许整串匹配。像 running / failed / created 这类词既是状态徽标,
    // 也是英文句子里的普通单词; 一旦允许子串替换, "The server is running" 会
    // 被改成 "The server is 运行中"。阈值取 8 个字符: 更短的几乎都是独立标签。
    var EXACT_ONLY_MAX = 8;
    var subKeys = keys.filter(function (k) { return k.length >= EXACT_ONLY_MAX; });
    // 两侧都要求词边界: 否则 "Knowledges" 会因为命中了 "Knowledge" 而被替换成
    // "知识库s" —— 这是实测在仪表盘上真实出现过的 bug。加了断言之后, 只有独立
    // 出现的整个单词/短语才会被替换。
    var SUB_RE = subKeys.length
        ? new RegExp('(?<![A-Za-z])(?:' + subKeys.map(escapeRe).join('|') + ')(?![A-Za-z])', 'g')
        : null;

    function translate(value) {
        if (!value || typeof value !== 'string') { return value; }
        var trimmed = value.trim();
        if (DICT[trimmed] !== undefined) {
            return value.replace(trimmed, DICT[trimmed]);
        }
        // 子串替换只作用于短文本。界面里的拼接串(如 "Upload files (3)")很短;
        // 长文本几乎都是 agent 日志、技术报告或正文, 部分替换会让它们中英夹杂,
        // 得不偿失 —— 宁可留英文。
        if (!SUB_RE || trimmed.length > 80) { return value; }
        SUB_RE.lastIndex = 0;
        var out = value.replace(SUB_RE, function (m) {
            return DICT[m] !== undefined ? DICT[m] : m;
        });
        return out;
    }

    function inSkipZone(node) {
        var el = node.parentElement;
        if (!el || !el.closest) { return false; }
        try { return !!el.closest(SKIP_SELECTOR); } catch (e) { return false; }
    }

    // ---------------------------------------------------------------- 翻译动作
    function doTextNode(node) {
        var v = node.nodeValue;
        if (!v || !/\S/.test(v)) { return; }
        if (inSkipZone(node)) { return; }
        var nv = translate(v);
        if (nv !== v) { node.nodeValue = nv; }
    }

    function doElement(el) {
        if (!el || el.nodeType !== 1 || !el.getAttribute) { return; }
        for (var i = 0; i < ATTRS.length; i++) {
            var a = ATTRS[i];
            var val = el.getAttribute(a);
            if (val) {
                var nv = translate(val);
                if (nv !== val) { el.setAttribute(a, nv); }
            }
        }
    }

    function walkText(root) {
        if (root.nodeType === 3) { doTextNode(root); return; }
        if (root.nodeType !== 1) { return; }
        doElement(root);
        var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
        var n, batch = [];
        while ((n = walker.nextNode())) { batch.push(n); }
        for (var i = 0; i < batch.length; i++) { doTextNode(batch[i]); }
        var els = root.querySelectorAll('[placeholder],[title],[aria-label],[alt]');
        for (var j = 0; j < els.length; j++) { doElement(els[j]); }
    }

    // ---------------------------------------------------------------- 观察
    var busy = false;

    function onMutations(muts) {
        if (busy) { return; }
        busy = true;
        try {
            for (var i = 0; i < muts.length; i++) {
                var m = muts[i];
                if (m.type === 'characterData') {
                    doTextNode(m.target);
                } else if (m.type === 'attributes') {
                    doElement(m.target);
                } else if (m.addedNodes) {
                    for (var k = 0; k < m.addedNodes.length; k++) { walkText(m.addedNodes[k]); }
                }
            }
        } catch (e) { /* 单次失败不应中断观察 */ }
        // 标题由 React 在挂载后才设置, 所以每轮变更都补一次
        syncTitle();
        busy = false;
    }

    // 浏览器标题形如 "Login — PentAGI": 是页面名与品牌名拼成的, 而正文里短键
    // 只做整串匹配(避免误伤英文句子)。标题是安全上下文, 因此允许按词替换。
    var TITLE_RE = null;
    function translateTitle(t) {
        if (!t) { return t; }
        var trimmed = t.trim();
        if (DICT[trimmed] !== undefined) { return DICT[trimmed]; }
        if (!TITLE_RE) {
            var tk = keys.filter(function (k) { return k.length >= 3; });
            TITLE_RE = tk.length ? new RegExp('\\b(?:' + tk.map(escapeRe).join('|') + ')\\b', 'g') : false;
        }
        if (!TITLE_RE) { return t; }
        TITLE_RE.lastIndex = 0;
        return t.replace(TITLE_RE, function (m) { return DICT[m] !== undefined ? DICT[m] : m; });
    }

    function syncTitle() {
        var cur = document.title;
        var next = translateTitle(cur);
        if (next && next !== cur) { document.title = next; }
    }

    function shouldRun() {
        try {
            if (window.location.search.indexOf('lang=en') !== -1) { return false; }
            return window.localStorage.getItem('pentagi_lang') !== 'en';
        } catch (e) { return true; }
    }

    var observer = null;

    function start() {
        if (!shouldRun()) { return; }
        if (document.body) { walkText(document.body); }
        syncTitle();
        observer = new MutationObserver(onMutations);
        observer.observe(document.documentElement, {
            childList: true,
            subtree: true,
            characterData: true,
            attributes: true,
            attributeFilter: ATTRS
        });
        // 标题可能在首次渲染后才写入, 单独盯一小段时间
        var ticks = 0;
        var t = setInterval(function () { syncTitle(); if (++ticks > 40) { clearInterval(t); } }, 250);
    }

    // 方便手动切换: pentagiLang('en') / pentagiLang('zh') 后刷新
    window.pentagiLang = function (lang) {
        try {
            if (lang === 'en') { window.localStorage.setItem('pentagi_lang', 'en'); }
            else { window.localStorage.removeItem('pentagi_lang'); }
        } catch (e) {}
        window.location.reload();
    };

    window.pentagiZhStats = function () {
        return { entries: keys.length, active: !!observer, enabled: shouldRun() };
    };

    // 暴露匹配函数, 便于在无浏览器环境(如 Node)下做离线单元测试
    window.pentagiZhTranslate = translate;

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', start);
    } else {
        start();
    }
})();
