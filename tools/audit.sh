#!/bin/bash
# 发布前隐私核查 —— 确认仓库里不含任何个人/机器信息。
# 任何人可重跑复核:  bash tools/audit.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "=============================================="
echo " 隐私核查: $ROOT"
echo "=============================================="

echo
echo "=== 0. 被检查的文件(排除 .git) ==="
find . -path ./.git -prune -o -type f -print | sort | sed 's/^/  /'

fail=0
scan() {  # scan <标签> <正则>
    local label="$1" re="$2" n
    n=$(grep -rEn --exclude-dir=.git "$re" . 2>/dev/null | wc -l)
    if [ "$n" -eq 0 ]; then
        printf '  ✅ %s\n' "$label"
    else
        printf '  ❌ %s —— %s 处\n' "$label" "$n"
        grep -rEn --exclude-dir=.git "$re" . 2>/dev/null | head -5 | sed 's/^/       /'
        fail=1
    fi
}

echo
echo "=== 1. 凭据与密钥 ==="
scan "API key / 令牌形态"   '(sk-[A-Za-z0-9]{16,}|ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{10,})'
scan "JWT / Bearer"         '(Bearer [A-Za-z0-9._-]{20,}|eyJ[A-Za-z0-9._-]{20,})'
scan "bcrypt 哈希"          '\$2[aby]\$[0-9]{2}\$[A-Za-z0-9./]{40,}'
scan "私钥文件头"           'BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY'
scan "密码赋值语句"         '(password|passwd|secret)[[:space:]]*=[[:space:]]*["'"'"'][^"'"'"']{6,}'

echo
echo "=== 2. 网络标识 ==="
# 排除项说明:
#   RFC 5737 (192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24) 是保留给文档示例
#   的地址段, 出现在测试夹具里属正常;
#   tools/audit.sh 自身必然含有 URL/IP 的正则文本, 参与扫描只会自匹配。
DOC_IP='^(192\.0\.2\.|198\.51\.100\.|203\.0\.113\.)'
n=$(grep -rEoh --exclude-dir=.git --exclude=audit.sh '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' . 2>/dev/null \
    | grep -vE "$DOC_IP" | wc -l)
if [ "$n" -eq 0 ]; then
    echo "  ✅ 无常规 IPv4 地址 (仅允许 RFC 5737 文档段)"
else
    echo "  ❌ 出现 IPv4 地址 —— $n 处:"
    grep -rEn --exclude-dir=.git --exclude=audit.sh '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' . 2>/dev/null \
        | grep -vE "$DOC_IP" | head -5 | sed 's/^/       /'
    fail=1
fi
scan "邮箱地址"             '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'

# 允许出现的 URL 之外一律视为可疑。grep -E 是 POSIX ERE, 不支持负向先行断言,
# 所以先取出全部 URL 再过滤。分隔符要把反引号、大括号与全角标点算进去, 否则
# Markdown 代码标记或 shell 变量展开的括号会被粘进 URL 里造成误报。
# raw.githubusercontent.com 是本项目快速安装命令的地址, 属白名单。
ALLOW='^https://github\.com/|^https://raw\.githubusercontent\.com/|^https://localhost:8443'
URLRE='https?://[^"'"'"' )>}`,、。，；：（）]+'
n=$(grep -rEoh --exclude-dir=.git --exclude=audit.sh "$URLRE" . 2>/dev/null \
    | sort -u | grep -vE "$ALLOW" | wc -l)
if [ "$n" -eq 0 ]; then
    echo "  ✅ URL 均在白名单内 (github.com 与 localhost:8443)"
else
    echo "  ❌ 出现白名单外的 URL —— $n 个:"
    grep -rEoh --exclude-dir=.git --exclude=audit.sh "$URLRE" . 2>/dev/null \
        | sort -u | grep -vE "$ALLOW" | sed 's/^/       /'
    fail=1
fi

echo
echo "=== 3. 本机信息 ==="
scan "Windows 盘符路径"     '[A-Za-z]:\\'
scan "WSL 挂载路径"         '/mnt/[a-z]/'
scan "用户主目录路径"       '/(home|Users)/[A-Za-z0-9._-]+/'
scan "常见主机名模式"       '\b(DESKTOP|LAPTOP)-[A-Z0-9]{4,}\b'

echo
echo "=== 4. 词典中的可疑内容(英文原文本身不该含个人信息) ==="
n=$(grep -oE '"[^"]{6,}"[[:space:]]*:' zh-dict.js 2>/dev/null | grep -iE 'token|secret|password|key|@|http' | wc -l)
if [ "$n" -eq 0 ]; then
    echo "  ✅ 词典键名中无凭据相关字样"
else
    echo "  ⚠️  词典中有 $n 个键名含敏感字样, 请人工确认是否为界面标签:"
    grep -oE '"[^"]{6,}"[[:space:]]*:' zh-dict.js 2>/dev/null | grep -iE 'token|secret|password|key|@|http' | head -8 | sed 's/^/       /'
fi

echo
if [ "$fail" -eq 0 ]; then
    echo "=============================================="
    echo " ✅ 核查通过: 未发现个人/机器敏感信息"
    echo "=============================================="
else
    echo "=============================================="
    echo " ❌ 核查未通过: 请处理上面标记的问题"
    echo "=============================================="
    exit 1
fi
