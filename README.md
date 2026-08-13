# DeepSeek Harness macOS App

把 DeepSeek Harness 的 Web GUI 封装成本机可直接运行的 macOS 应用（`DeepSeek Harness.app`）。

A native macOS shell for the DeepSeek Harness Web GUI: double-click the app and it
starts (or attaches to) the local `dsh web` server and shows the UI in its own window.

## 特性 / What it does

- 双击启动，自带窗口（WKWebView），不依赖浏览器。
- 自动启动本地 `dsh web` 服务（默认端口 3080）；若端口上已有正在运行的 Harness，则直接连接，不重复启动。
- 退出应用时，由应用启动的服务会随之停止（连接到已有服务时不干预）。
- 无证书、无公证（仅 ad-hoc 签名），仅限本机使用，不可分发。
- 日志位置：`~/Library/Logs/DeepSeekHarness/`（应用日志 `app.log`，服务日志 `server.log`）。

## 构建 / Build

```sh
bash scripts/macos-app/build-app.sh
```

默认安装到 `~/Applications/`。可覆盖的环境变量：

| 变量 | 默认值 |
| --- | --- |
| `APP_NAME` | `DeepSeek Harness` |
| `PORT` | `3080` |
| `NODE_PATH` | 自动检测（nvm / Homebrew / PATH） |
| `BUNDLE_ID` | `com.deepseek-ai.harness.local` |
| `VERSION` | `0.1.0` |
| `INSTALL_DIR` | `~/Applications` |
| `NO_INSTALL` | `1` 时只构建不安装 |

## 发给朋友 / Distribution

普通构建依赖本机仓库路径，**不能直接发给别人**。便携构建把 harness 代码与 node
运行环境全部打进 app（运行时按 bundle 相对路径解析，app 拖到任何位置都能用）：

```sh
PORTABLE=1 ZIP=1 DMG=1 bash scripts/macos-app/build-app.sh
```

产物在 `scripts/macos-app/dist/`：

- `DeepSeek-Harness-macOS-arm64.dmg` —— 推荐；朋友双击挂载后把 app 拖进「应用程序」
- `DeepSeek-Harness-macOS-arm64.zip` —— 备用（可做分卷：`zip -s 900m DeepSeek-Harness-macOS-arm64.zip --out dsh-parts.zip`）
- `使用说明.txt` —— 随包附给朋友的说明

朋友机器要求：Apple Silicon（M 系列芯片）、macOS 14+；首次打开需右键 → 打开
（应用未签名公证）。朋友需要自己的 DeepSeek API Key（界面里配置）。

## 使用 / Usage

1. 双击 `~/Applications/DeepSeek Harness.app`（首次如被 Gatekeeper 拦截：右键 → 打开）。
2. 窗口内即 Harness Web GUI；API Key 等凭据沿用 `~/.dsh` 与仓库根目录 `.env`。

## 注意事项 / Notes

- 应用以源码方式启动服务：`node --import tsx/esm apps/cli/src/bin.ts web --port <PORT>`，工作目录为仓库根目录；改动仓库源码后重启应用即生效。
- 更换 node 路径或端口后需重新运行构建脚本（路径与端口编译期写入应用）。
- 构建产物（`scripts/macos-app/build/`）不入库。
