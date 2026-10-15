#!/usr/bin/env python3
"""合并 dict/*.json, 生成前端可用的 zh-dict.js。

用法(仓库根目录):
    python3 tools/build-dict.py
或显式指定:
    python3 tools/build-dict.py <源目录> <输出文件>

规则:
  - dict/ 下所有 part*.json 都会被合并; 文件名排序决定优先级, 靠后的覆盖靠前的,
    因此 part9-overrides.json 用于跨批次一致性裁决。
  - 下划线开头的键视为注记, 不进入词典。
  - 键会去掉首尾空白(DOM 匹配用的是 trim 后的文本)。
  - 译文不做 strip: 前缀片段的译文可以保留尾随空格。HTML 会折叠连续空白,
    所以多一个空格无害, 少一个空格却会让 "推送到2026" 粘在一起。
"""
import glob
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'dict')
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, 'zh-dict.js')

merged = {}
files = sorted(glob.glob(os.path.join(src, 'part*.json')))
if not files:
    print('错误: 在 %s 找不到任何 part*.json' % src)
    sys.exit(1)

for f in files:
    name = os.path.basename(f)
    try:
        with open(f, encoding='utf-8') as fh:
            data = json.load(fh)
    except Exception as e:
        print('  跳过 %s: 不是合法 JSON (%s)' % (name, e))
        continue
    if not isinstance(data, dict):
        print('  跳过 %s: 顶层不是对象' % name)
        continue
    before = len(merged)
    for k, v in data.items():
        if not isinstance(k, str) or not isinstance(v, str):
            continue
        if k.startswith('_'):
            continue
        k2 = k.strip()
        v2 = v.rstrip('\r\n')
        if k2 and v2.strip() and k2 != v2:
            merged[k2] = v2
    print('  %-24s %4d 条, 累计 %4d (+%d)' % (name, len(data), len(merged), len(merged) - before))

with open(out, 'w', encoding='utf-8') as fh:
    fh.write('/* 自动生成, 请勿手改 —— 源: dict/part*.json, 由 tools/build-dict.py 生成 */\n')
    fh.write('window.__PENTAGI_ZH_DICT = ')
    fh.write(json.dumps(merged, ensure_ascii=False, indent=0, sort_keys=True))
    fh.write(';\n')

print('  完成: %d 条 -> %s' % (len(merged), out))
