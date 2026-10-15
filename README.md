# PentAGI 中文界面补丁

给 [PentAGI](https://github.com/vxcontrol/pentagi) 的 Web 界面加一层中文（约 960 条词条）。

**不改镜像、不改后端、不改数据库，一键安装与卸载。**

> ⚠️ **非官方项目**：与 PentAGI Development Team 无隶属关系，未获其背书。
> 界面英文原文来自 PentAGI（MIT，Copyright (c) 2025 PentAGI Development Team），中文译文为本项目原创。详见 [LICENSE](LICENSE) 与 [NOTICE](NOTICE)。
>
> ⚠️ **合法使用**：PentAGI 是渗透测试工具，请仅对你拥有明确授权的目标使用。

---

## 快速安装

```bash
curl -fsSL https://raw.githubusercontent.com/Qzscode/pentagi-zh/main/install.sh | bash
```

## 安装（手动下载）

网络不稳时用这个，不依赖 `raw.githubusercontent.com` 域名：

```bash
curl -fsSL https://github.com/Qzscode/pentagi-zh/archive/refs/heads/main.tar.gz | tar xz -C /tmp && bash /tmp/pentagi-zh-main/install.sh
```

装完**强制刷新浏览器**（`Ctrl+Shift+R`）。

**前置条件**：pentAGI 已用 docker compose 部署并运行中（`docker compose ps` 能看到 `pentagi` 容器），机器上有 `curl`、`tar`、`docker`。

**pentAGI 装在非默认目录**（默认 `/opt/pentagi`）时，把目录作为参数传入：

```bash
curl -fsSL https://raw.githubusercontent.com/Qzscode/pentagi-zh/main/install.sh | bash -s -- /your/pentagi
```

**docker 需要 root** 时，在 `bash` 前加 `sudo`。

## 卸载

```bash
curl -fsSL https://raw.githubusercontent.com/Qzscode/pentagi-zh/main/uninstall.sh | bash
```

数据、账号、配置完全不受影响。

## 切回英文

浏览器控制台执行：

```js
pentagiLang('en')    // 切英文（会记住）
pentagiLang('zh')    // 切回中文
```

也可在网址后加 `?lang=en`。

---

## 维护者备注

升级 pentAGI 镜像后需**重跑一次安装**：补丁会遮蔽容器内的 `index.html`，新镜像的资源 hash 与之不匹配会导致白屏。安装脚本从镜像层现场重建，重跑即可。

词典源码在 `dict/`，改完重新生成并自测：

```bash
python3 tools/build-dict.py      # dict/*.json -> zh-dict.js
node tools/test-translator.js    # 离线单元测试
bash tools/audit.sh              # 隐私核查
```
