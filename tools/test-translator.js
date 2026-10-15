#!/usr/bin/env node
/* 翻译器的离线单元测试 —— 无需浏览器即可验证最关键的部分。
 *
 * 用法(仓库根目录):  node tools/test-translator.js
 *
 * 覆盖: 词典装载、整串匹配、子串替换、未命中回退、技术载荷保护、
 *       长文本保护、短词整串匹配、正则性能。
 */
const fs = require('fs');
const vm = require('vm');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
let pass = 0, fail = 0;
function check(name, cond, extra) {
    if (cond) { pass++; console.log('  PASS  ' + name); }
    else { fail++; console.log('  FAIL  ' + name + (extra ? '  -> ' + extra : '')); }
}

// 最小 DOM 桩: readyState 保持 loading, 使 start() 不触发, 从而只测纯匹配逻辑
const sandbox = {
    console,
    NodeFilter: { SHOW_TEXT: 4 },
    MutationObserver: function () { this.observe = function () {}; },
    document: { readyState: 'loading', addEventListener: function () {}, title: 'PentAGI' },
    window: {},
};
sandbox.window.localStorage = undefined;
vm.createContext(sandbox);

vm.runInContext(fs.readFileSync(path.join(ROOT, 'zh-dict.js'), 'utf8'), sandbox, { filename: 'zh-dict.js' });
vm.runInContext(fs.readFileSync(path.join(ROOT, 'zh-cn.js'), 'utf8'), sandbox, { filename: 'zh-cn.js' });

const DICT = sandbox.window.__PENTAGI_ZH_DICT;
const t = sandbox.window.pentagiZhTranslate;

console.log('词典条目数: ' + Object.keys(DICT).length);
console.log('');
console.log('--- 1. 词典装载 ---');
check('词典非空(>50 条)', Object.keys(DICT).length > 50, '仅 ' + Object.keys(DICT).length + ' 条');
check('翻译函数已导出', typeof t === 'function');

const keys = Object.keys(DICT);
console.log('');
console.log('--- 2. 整串精确匹配 (抽样 40 条) ---');
let exactFail = [];
const step = Math.max(1, Math.floor(keys.length / 40));
const sample = keys.filter((_, i) => i % step === 0).slice(0, 40);
for (const k of sample) {
    if (t(k) !== DICT[k]) { exactFail.push(k + ' => ' + t(k)); }
}
check('抽样 40 条全部命中', exactFail.length === 0, exactFail.slice(0, 3).join(' | '));

console.log('');
console.log('--- 3. 首尾空白容错 ---');
check('保留原空白并替换正文',
    t('   ' + sample[0] + '   ') === '   ' + DICT[sample[0]] + '   ',
    JSON.stringify(t('   ' + sample[0] + '   ')));

console.log('');
console.log('--- 4. 子串替换 (界面里常见的拼接文本) ---');
// 必须挑 >=8 字符的键: 更短的键按设计只做整串匹配
const subBase = keys.filter((k) => k.length >= 8)[0];
if (subBase) {
    const embedded = 'xx ' + subBase + ' yy';
    check('句中子串被替换 [' + subBase + ']', t(embedded).indexOf(DICT[subBase]) !== -1, t(embedded));
} else {
    check('(词典中没有 >=8 字符的键, 跳过)', true);
}

console.log('');
console.log('--- 5. 技术载荷必须原样保留 ---');
const technical = [
    // 192.0.2.0/24 是 RFC 5737 专门保留给文档示例的地址段, 不是真实主机
    'nmap -sV -p- 192.0.2.10',
    'SELECT * FROM users WHERE id = 1;',
    'ls -la /opt/pentagi && docker ps',
    'CVE-2021-44228',
    'curl -k https://localhost:8443/api/v1/info',
    'aGVsbG8gd29ybGQ=',
];
let techFail = [];
for (const s of technical) { if (t(s) !== s) { techFail.push(s + ' => ' + t(s)); } }
check('命令行/SQL/URL/base64 未被改动', techFail.length === 0, techFail.join(' | '));

console.log('');
console.log('--- 6. 未命中回退英文 ---');
const unknown = 'Zzz Qqq Www Not In Dictionary 12345';
check('未命中时原样返回', t(unknown) === unknown, t(unknown));
check('空值安全', t('') === '' && t(null) === null && t(undefined) === undefined);

console.log('');
console.log('--- 7. 长文本不做子串替换 (保护 agent 日志与技术正文) ---');
const SUB = subBase || keys[0];
const longLine = ('Report: ' + SUB + ' was generated after analysing every host in scope and correlating the findings. ').repeat(2);
check('超过 80 字符的文本保持原样', t(longLine) === longLine, t(longLine).slice(0, 70));
const shortLine = 'x ' + SUB + ' y';
check('短文本仍做子串替换', t(shortLine) !== shortLine, t(shortLine));

console.log('');
console.log('--- 8. 短词只做整串匹配 (保护英文句子) ---');
if (DICT['running']) {
    check('独立状态词被翻译', t('running') === DICT['running'], t('running'));
    const sentence = 'The server is running now';
    check('句子中的同形词不受影响', t(sentence) === sentence, t(sentence));
} else {
    check('(词典中无 running, 跳过)', true);
}

console.log('');
console.log('--- 9. 词边界断言 (防 "知识库s" 这类半截替换) ---');
if (DICT['Knowledge']) {
    check('Knowledges 整词命中', t('Knowledges') === DICT['Knowledges'], t('Knowledges'));
    const embedded2 = 'x Knowledge y';
    check('独立 Knowledge 被替换', t(embedded2).indexOf(DICT['Knowledge']) !== -1, t(embedded2));
} else {
    check('(词典中无 Knowledge, 跳过)', true);
}

console.log('');
console.log('--- 10. 性能 (正则回溯风险) ---');
const many = [];
for (let i = 0; i < 3000; i++) { many.push(sample[i % sample.length] + ' #' + i); }
let t0 = Date.now();
t(longLine);
const longMs = Date.now() - t0;
t0 = Date.now();
for (const s of many) { t(s); }
const manyMs = Date.now() - t0;
check('单条长文本 < 50ms', longMs < 50, longMs + 'ms');
check('3000 条 < 2000ms', manyMs < 2000, manyMs + 'ms');
console.log('        长文本 ' + longMs + 'ms, 3000 条 ' + manyMs + 'ms');

console.log('');
console.log('============================');
console.log('通过 ' + pass + ' 项, 失败 ' + fail + ' 项');
process.exit(fail > 0 ? 1 : 0);
