# DeepSeek Harness macOS App

DeepSeek Harness 的 macOS 原生客户端。

## 这是什么？

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 是 DeepSeek 官方的 AI 编程助手框架，功能强大但**部署门槛极高**：

- 需要安装 Node.js 22+、pnpm、git
- 需要 clone 整个仓库、安装依赖、编译
- 需要配置环境变量、处理各种路径问题
- 对非技术用户来说，几乎不可能跑起来

**这个项目的目的就是让普通人也能用上 DeepSeek Harness。**

我把整个 Harness 打包成了一个 macOS 原生应用：
- 内置 Node.js 运行时和所有依赖（~1.5GB）
- 双击即可运行，无需任何配置
- 原生窗口（非浏览器），体验更好

## 为什么要做这个？

因为我发现身边很多人想用 DeepSeek Harness，但被部署流程劝退：

> "我按照官方文档装了一下午，还是跑不起来"
>
> "Node.js 版本不对、pnpm 装不上、依赖冲突..."
>
> "太麻烦了，我还是用网页版吧"

**技术应该服务于人，而不是让人去适应技术。**

这个 app 就是为了解决这个问题：下载、安装、双击、开始用。就这么简单。

## 下载安装

### 系统要求

- **Apple Silicon Mac**（M1/M2/M3/M4 芯片）
- **macOS 14.0+**（Sonoma 或更新）
- **DeepSeek API Key**（需要自己申请）

> ⚠️ 不支持 Intel 芯片的 Mac，也不支持 Windows/Linux。

### 下载

从 [Releases 页面](https://github.com/ZeroxZhang/deepseek-harness-app/releases) 下载最新版本：

- **推荐**：`DeepSeek-Harness-macOS-arm64.dmg`（757MB）
- 备选：`DeepSeek-Harness-macOS-arm64.zip`（529MB，适合网络较慢的情况）

### 安装

1. **双击 DMG 文件**，会挂载一个虚拟磁盘
2. **把 `DeepSeek Harness.app` 拖到「应用程序」文件夹**
3. 关闭 DMG 窗口（可以右键弹出，或拖到废纸篓）

## 首次打开（重要！）

由于这个 app 没有 Apple 开发者签名，macOS 会阻止你直接打开。**必须按以下步骤操作**：

### 方法一：右键打开（推荐）

1. 打开「应用程序」文件夹
2. **右键点击** `DeepSeek Harness.app`（不是左键！）
3. 选择「打开」
4. 弹出的对话框中，再次点击「打开」

### 方法二：命令行解除限制

如果右键打开还是不行，打开「终端」app，运行：

```bash
xattr -cr ~/Applications/DeepSeek\ Harness.app
```

然后再双击打开 app。

### 为什么会这样？

macOS 有安全机制（Gatekeeper），会阻止未签名的应用。这个命令告诉系统"我信任这个 app"。只需要执行一次，以后就正常了。

## 开始使用

1. **打开 app**（按上面的方法）
2. 等待 10-30 秒，app 会在后台启动服务（首次启动会创建配置文件）
3. 窗口出现后，点击左下角的**设置图标**
4. 输入你的 **DeepSeek API Key**（在 [platform.deepseek.com](https://platform.deepseek.com) 申请）
5. 开始使用！

### 日志位置

如果遇到问题，可以查看日志：

```bash
# 应用日志
cat ~/Library/Logs/DeepSeekHarness/app.log

# 服务日志
cat ~/Library/Logs/DeepSeekHarness/server.log
```

## 常见问题

### Q: 一直显示"正在启动..."？

A: 首次启动需要创建配置文件，可能需要 30 秒。如果超过 1 分钟，检查日志：

```bash
tail -f ~/Library/Logs/DeepSeekHarness/app.log
```

### Q: 提示"无法连接到服务"？

A: 可能是端口被占用。退出 app，检查 3080 端口：

```bash
lsof -i :3080
```

如果有其他程序占用，杀掉它或者修改 app 的端口配置。

### Q: 可以用自己的 API Key 吗？

A: 当然可以！这就是这个 app 的设计目的。在设置里输入你自己的 DeepSeek API Key 即可。

### Q: 数据安全吗？

A: 所有数据都保存在你本地（`~/.dsh/` 目录），不会上传到任何地方。API Key 也只存在你的电脑上。

### Q: 可以自动更新吗？

A: 目前不支持自动更新。新版本发布后，需要手动下载替换。

## 开发者指南

如果你想自己构建这个 app：

### 环境要求

- macOS 14+
- Xcode Command Line Tools（`xcode-select --install`）
- Node.js 22+
- 完整的 deepseek-harness 仓库源码

### 构建步骤

```bash
# 1. Clone 源码
git clone https://github.com/deepseek-ai/deepseek-harness.git
cd deepseek-harness

# 2. 安装依赖
pnpm install

# 3. 构建便携版 app（内置 Node.js 和所有依赖）
PORTABLE=1 ZIP=1 DMG=1 bash scripts/macos-app/build-app.sh

# 4. 产物在 scripts/macos-app/dist/
ls scripts/macos-app/dist/
```

### 构建选项

| 环境变量 | 说明 | 默认值 |
|---------|------|--------|
| `PORTABLE` | 是否打包成便携版 | `0` |
| `ZIP` | 是否生成 ZIP | `0` |
| `DMG` | 是否生成 DMG | `0` |
| `APP_NAME` | 应用名称 | `DeepSeek Harness` |
| `PORT` | 服务端口 | `3080` |

## 致谢

- [DeepSeek](https://deepseek.com) - 提供了强大的 AI 模型
- [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) - 官方的 AI 编程助手框架

## License

MIT
