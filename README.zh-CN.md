# Flutter Vibe Coding

面向 Flutter 的应用内 vibe coding。

[English](README.md)

这个仓库提供了一条本地开发闭环：Flutter 应用通过 UME 暴露应用内 AI 面板，把自然语言编辑请求发送到本地服务端，再把代码修改结果回写到 Flutter 工程，并按需触发热重载。

## 当前状态

实验性项目，但已经可以跑通。

它当前更适合本地开发和原型验证，而不是生产环境部署。如果你想验证“在运行中的 Flutter 应用里直接描述 UI 修改，再让系统回写代码”这件事，这个仓库就是一个可运行起点。

## 它能做什么

- 在 Debug Flutter 应用里嵌入 `AI Vibe Panel`
- 把自然语言编辑请求发给本地服务
- 提供可复现的 mock adapter 便于演示
- 提供 Codex adapter 便于做更广泛的代码修改
- 把命令进度和审批状态流式回传给客户端
- 在本地托管流程里尝试触发热重载

## 仓库结构

```text
.
|-- flutter_vibe_app/   # Flutter 客户端与 UME 集成
|-- packages/
|   `-- flutter_vibe_ume/  # 可复用的 UME vibe-coding 包
|-- local_ai_server/    # 本地 TypeScript 服务端与 agent 编排
|-- docs/               # 项目文档
`-- .github/            # CI 与社区协作文件
```

## 架构流程

1. Flutter 应用在 Debug 模式下运行，并启用 UME。
2. `AI Vibe Panel` 收集指令和可选运行时上下文。
3. 面板通过 HTTP 把请求发送给本地服务端。
4. 服务端把请求交给 adapter（`mock` 或 `codex`）。
5. Adapter 修改 Flutter 工程并返回变更文件。
6. 服务端按配置触发热重载，并把状态流式返回客户端。

更多细节见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 快速开始

### 前置条件

- Flutter SDK
- Node.js 22+ 更推荐
- 能运行 Flutter Debug 构建的本地环境

### 1. 启动本地服务端

```bash
cd local_ai_server
npm ci
FLUTTER_PROJECT_PATH=../flutter_vibe_app npm run start
```

如果你想使用 Codex adapter：

```bash
cd local_ai_server
npm ci
FLUTTER_PROJECT_PATH=../flutter_vibe_app npm run start:codex
```

### 2. 运行 Flutter 应用

```bash
cd flutter_vibe_app
flutter pub get
flutter run -d chrome
```

如果 Android 或 iOS 本地链路已经就绪，也可以直接运行：

```bash
flutter run
```

### 3. 在应用中配置服务地址

打开 UME，进入 `AI Vibe Panel`，保存你的本地服务地址。

本机调试可直接使用：

```text
http://127.0.0.1:8787
```

如果是真机调试，手机和电脑在同一局域网内时，请填写电脑的局域网 IP：

```text
http://192.168.x.x:8787
```

## 示例指令

```text
把按钮改成绿色，并把文案改成 Start
```

在 mock 模式下，这会修改 [flutter_vibe_app/lib/home_page.dart](flutter_vibe_app/lib/home_page.dart) 里的首页常量。

## 环境变量

### Server

- `PORT`: 服务端端口，默认 `8787`
- `HOST`: 监听地址，默认 `0.0.0.0`
- `FLUTTER_PROJECT_PATH`: Flutter 工程路径
- `AGENT_ADAPTER`: `mock` 或 `codex`
- `AUTO_START_FLUTTER`: 是否自动拉起并托管 `flutter run`
- `FLUTTER_RELOAD_COMMAND`: 自定义重载命令

### Codex adapter

- `CODEX_BIN`: 覆盖 Codex 可执行文件路径
- `CODEX_MODEL`: 透传 `--model` 给 `codex exec`
- `CODEX_PROFILE`: 透传 `--profile` 给 `codex exec`
- `CODEX_COMMAND`: 覆盖完整 Codex 启动命令

## 开发

### 检查 server 类型

```bash
cd local_ai_server
npm run typecheck
```

### 分析并测试 Flutter 应用

```bash
cd flutter_vibe_app
flutter analyze
flutter test
```

## 当前限制

- 这仍然是本地优先的原型，不是面向公网的安全执行平台。
- mock adapter 只覆盖少量演示规则。
- 热重载自动化能力依赖 Flutter 进程的启动方式。
- Web 支持受 UME 相关包兼容性约束。

## Roadmap

- 更好的组件选择与运行时上下文采集
- 更完整的审批与安全策略
- 多轮编辑历史
- 面向生成改动的回归测试
- 更稳定的真机工作流

## 参与贡献

欢迎提 issue 和 PR，先看 [CONTRIBUTING.md](CONTRIBUTING.md)。

如果是安全相关问题，请走 [SECURITY.md](SECURITY.md)。

## License

本项目使用 MIT License，见 [LICENSE](LICENSE)。
