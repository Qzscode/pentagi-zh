#!/bin/bash
# ============================================================================
#  PentAGI 中文界面补丁 —— 安装
#
#  三种用法都支持:
#    1) 快速安装(单文件自取所需资源):
#         curl -fsSL https://raw.githubusercontent.com/Qzscode/pentagi-zh/main/install.sh | bash
#    2) 归档安装(整包下载后执行, 不依赖 raw 域名):
#         curl -fsSL .../archive/refs/heads/main.tar.gz | tar xz -C /tmp \
#           && bash /tmp/pentagi-zh-main/install.sh
#    3) 本地克隆后执行:
#         bash install.sh [pentagi项目目录]
#
#  默认项目目录 /opt/pentagi, 也可作为第一个参数传入。
#
#  作者: pentagi-zh contributors   MIT License   非官方项目, 详见 NOTICE
# ============================================================================
set -euo pipefail

REPO="${1:-/opt/pentagi}"
RAW_BASE="${PENTAGI_ZH_RAW:-https://raw.githubusercontent.com/Qzscode/pentagi-zh/main}"
DEST="$REPO/zh-i18n"
OVERRIDE="$REPO/docker-compose.override.yml"

# 脚本所在目录: 经管道执行(curl|bash)时它没有意义, 因此必须能优雅退化
SELF="${BASH_SOURCE[0]:-$0}"
HERE="$(cd "$(dirname "$SELF")" 2>/dev/null && pwd || true)"

TMPDIR_Z=""
cleanup() { [ -n "$TMPDIR_Z" ] && rm -rf "$TMPDIR_Z"; return 0; }
trap cleanup EXIT

echo "=============================================="
echo " PentAGI 中文界面补丁 安装"
echo "=============================================="

# ---------------------------------------------------------------- 前置检查
command -v docker >/dev/null 2>&1 || { echo "错误: 未找到 docker"; exit 1; }
command -v curl   >/dev/null 2>&1 || { echo "错误: 未找到 curl"; exit 1; }

if [ ! -f "$REPO/docker-compose.yml" ]; then
    echo "错误: 在 $REPO 找不到 docker-compose.yml"
    echo "      请把 pentAGI 项目目录作为参数传入, 例如:"
    echo "      curl -fsSL $RAW_BASE/install.sh | bash -s -- /your/pentagi"
    exit 1
fi

cd "$REPO"
CID=$(docker compose ps -q pentagi 2>/dev/null | head -1 || true)
[ -n "$CID" ] || { echo "错误: pentagi 容器未运行, 请先执行 docker compose up -d"; exit 1; }
IMG=$(docker inspect "$CID" -f '{{.Config.Image}}')
echo "[1/6] 运行中的镜像: $IMG"

# ---------------------------------------------------------------- 定位补丁文件
# 本地有就用本地(克隆/归档场景); 没有就自己下载(单文件管道场景)。
SRC_DIR=""
if [ -n "$HERE" ] && [ -f "$HERE/zh-cn.js" ] && [ -f "$HERE/zh-dict.js" ]; then
    SRC_DIR="$HERE"
    echo "[2/6] 使用脚本同目录下的补丁文件"
else
    TMPDIR_Z="$(mktemp -d)"
    echo "[2/6] 脚本同目录没有补丁文件, 正在从远端获取"
    for f in zh-cn.js zh-dict.js; do
        if ! curl -fsSL --max-time 120 "$RAW_BASE/$f" -o "$TMPDIR_Z/$f"; then
            echo "错误: 下载 $f 失败 ($RAW_BASE/$f)"
            echo "      可改用归档方式安装:"
            echo "      curl -fsSL https://github.com/Qzscode/pentagi-zh/archive/refs/heads/main.tar.gz | tar xz -C /tmp && bash /tmp/pentagi-zh-main/install.sh"
            exit 1
        fi
        printf '        %-12s %6s 字节\n' "$f" "$(stat -c%s "$TMPDIR_Z/$f")"
    done
    SRC_DIR="$TMPDIR_Z"
fi

# ---------------------------------------------------------------- 生成 index.html
echo "[3/6] 从镜像层提取原始 index.html 并注入补丁"
docker run --rm --entrypoint cat "$IMG" /opt/pentagi/fe/index.html > /tmp/zh-orig-index.html 2>/dev/null || true
[ -s /tmp/zh-orig-index.html ] || { echo "错误: 无法从镜像层提取 index.html"; exit 1; }

mkdir -p "$DEST"
if grep -q 'zh-cn.js' /tmp/zh-orig-index.html; then
    # 镜像里本就带补丁标记(极少见), 直接沿用避免二次注入
    cp /tmp/zh-orig-index.html "$DEST/index.html"
    echo "      镜像内已含补丁标记, 直接沿用"
else
    grep -q '<script type="module"' /tmp/zh-orig-index.html || {
        echo "错误: index.html 结构与预期不符, 找不到 module 脚本插入点"; exit 1; }
    # 插在应用脚本之前: 经典脚本先于 module(延迟执行)运行,
    # 因此 MutationObserver 会在 React 首次渲染前就位, 不会漏掉首屏。
    sed 's#<script type="module"#<script src="/zh-dict.js"></script><script src="/zh-cn.js"></script><script type="module"#' \
        /tmp/zh-orig-index.html > "$DEST/index.html"
    echo "      已注入 (补丁先于应用加载)"
fi

# ---------------------------------------------------------------- 复制补丁文件
cp "$SRC_DIR/zh-cn.js"   "$DEST/zh-cn.js"
cp "$SRC_DIR/zh-dict.js" "$DEST/zh-dict.js"
echo "[4/6] 补丁文件就位, 词典条目: $(grep -o '":' "$DEST/zh-dict.js" | wc -l)"

# ---------------------------------------------------------------- compose 覆盖
if [ -f "$OVERRIDE" ] && ! grep -q 'zh-i18n' "$OVERRIDE"; then
    echo "警告: $OVERRIDE 已存在且与本补丁无关, 为免破坏你的配置已中止。"
    echo "      请手动把下面这段并入该文件后重新运行:"
    echo "------------------------------------------------------------------"
    echo "services:"
    echo "  pentagi:"
    echo "    volumes:"
    echo "      - ./zh-i18n/index.html:/opt/pentagi/fe/index.html:ro"
    echo "      - ./zh-i18n/zh-cn.js:/opt/pentagi/fe/zh-cn.js:ro"
    echo "      - ./zh-i18n/zh-dict.js:/opt/pentagi/fe/zh-dict.js:ro"
    echo "------------------------------------------------------------------"
    exit 1
fi
cat > "$OVERRIDE" <<'YML'
# 由 PentAGI 中文界面补丁生成。
# compose 会自动合并本文件与 docker-compose.yml; 只覆盖两个静态文件,
# 不涉及镜像、端口与环境变量。删除本文件即可完全恢复英文原版。
services:
  pentagi:
    volumes:
      - ./zh-i18n/index.html:/opt/pentagi/fe/index.html:ro
      - ./zh-i18n/zh-cn.js:/opt/pentagi/fe/zh-cn.js:ro
      - ./zh-i18n/zh-dict.js:/opt/pentagi/fe/zh-dict.js:ro
YML
echo "      已写入 $OVERRIDE"

# ---------------------------------------------------------------- 应用
echo "[5/6] 重建 pentagi 容器以应用挂载"
docker compose up -d pentagi 2>&1 | tail -3

echo "[6/6] 等待服务就绪并校验"
code=000
for _ in $(seq 1 30); do
    sleep 2
    code=$(curl -k -s -o /tmp/zh-idx.html -w '%{http_code}' --max-time 8 https://localhost:8443/ 2>/dev/null || echo 000)
    [ "$code" = "200" ] && break
done
echo "      首页 HTTP $code"
if grep -q 'zh-dict.js' /tmp/zh-idx.html 2>/dev/null; then
    echo "      ✅ 补丁已生效"
else
    echo "      ⚠️ 首页未见补丁脚本, 请强制刷新浏览器 (Ctrl+Shift+R) 后重试"
fi

echo
echo "=============================================="
echo " 安装完成。打开或强制刷新: https://localhost:8443/"
echo " 切英文(浏览器控制台): pentagiLang('en')"
echo " 卸载: 下载 uninstall.sh 后  bash uninstall.sh $REPO"
echo "=============================================="
