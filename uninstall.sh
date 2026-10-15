#!/bin/bash
# PentAGI 中文界面补丁 —— 卸载。恢复纯英文原版, 不动任何数据。
set -euo pipefail

REPO="${1:-/opt/pentagi}"
OVERRIDE="$REPO/docker-compose.override.yml"

echo "=== 卸载 PentAGI 中文界面补丁 ==="

if [ -f "$OVERRIDE" ] && grep -q 'zh-i18n' "$OVERRIDE"; then
    rm -f "$OVERRIDE"
    echo "  已删除 $OVERRIDE"
else
    echo "  未发现本补丁的覆盖文件 (可能已卸载)"
fi

cd "$REPO"
if docker compose ps -q pentagi >/dev/null 2>&1; then
    echo "  重建容器以移除挂载 ..."
    docker compose up -d pentagi 2>&1 | tail -3
fi

echo "  保留 $REPO/zh-i18n/ 目录(不影响运行), 如需彻底清除: rm -rf $REPO/zh-i18n"
echo
echo "完成。强制刷新浏览器 (Ctrl+Shift+R) 即回到英文原版。"
