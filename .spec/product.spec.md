# 产品规格：Mobile Vibe Coding Demo

## 问题类型

这是一个产品验证 + 工程验证问题。

产品风险是：开发者是否能把正在运行的 Flutter App 当作编辑入口，在 UI 上选中目标组件，用自然语言描述变更，然后让本地 agent 快速更新代码。

工程风险是：UME 是否能提供足够的运行时上下文，让 agent 修改正确的源码，而不是只靠一句很薄的 prompt 猜测。

## 已确认的基础事实

- UME 现有插件/kit 已经支持获取 widget 信息、widget 树结构、文件位置等调试信息，后续实现必须优先复用这些能力，而不是从零自研 inspector。
- 当前 server 已经预留并支持 Codex adapter 对接，后续真实修改代码的主路径应逐步从 mock adapter 迁移到 Codex adapter。
- App 端 AI 面板必须和 server 保持过程通信，展示 agent 当前进度，让用户能看到“正在分析 / 正在修改 / 正在 reload / 完成或失败”，而不是提交后干等。
- 为了可靠 hot reload，App 必须由 server 端启动或接管。只有 server 拥有 `flutter run` / `flutter attach` 进程 stdin，才能在修改代码后控制 reload。
- Hot restart 后 App 端必须还能看到单会话历史；MVP 不需要多会话，但当前会话必须可恢复。
- Server 端必须做严格安全控制，避免 App 下发的指令导致严重或毁灭级操作。
- Human in the loop 是分层能力：MVP 需要支持简单确认，用于依赖变更、需要重新编译 App、或自动修复失败等高影响场景；更复杂的 diff 审批流放入远期规划。

## 目标

构建一个最小跨端 Flutter demo，让 UME 成为 App 内的 AI 辅助改代码控制面板。

目标闭环是：

1. 用户从 server 端启动 Flutter App，或 server 接管已启动的 Flutter debug session。
2. UME 以悬浮工具面板形式打开。
3. 用户在运行中的 UI 上通过 UME 已有 inspector 能力选择或识别一个目标 widget/component。
4. UME AI 面板展示被选中组件的上下文。
5. 用户输入自然语言指令。
6. App 把指令 + server URL + 选中组件上下文发送到 Mac 本地 server。
7. App 端持续接收 server 进度事件，展示当前处理阶段。
8. Server 把运行时上下文和项目源码上下文组合起来。
9. Agent，优先 Codex adapter，修改 Flutter 工程代码。
10. Server 控制 Flutter debug session 执行 hot reload / hot restart。
11. Hot restart 后，AI 面板恢复当前单会话历史。
12. 用户验证变更，并继续下一轮迭代。

## 非目标

- 不做完整商业化 no-code 编辑器。
- 暂不实现语音输入。
- 第一版不做通用 Flutter AST 重构引擎。
- 在选中组件上下文跑通之前，不支持任意复杂多文件重构。
- MVP 阶段不针对不可信网络做完整安全加固。
- MVP 阶段不实现完整 diff 级审批流，但必须支持简单 Human in the loop 确认。
- MVP 不支持多会话管理，只支持单个当前会话的持久化和恢复。

## MVP 需求

### R1. UME 悬浮 AI 面板

AI 面板必须表现为悬浮工具窗口，而不是全屏路由页。

它必须允许用户：

- 查看和编辑 server URL。
- 重置为检测到的 / 默认的 Mac server URL。
- 输入自然语言指令。
- 查看当前发送状态。
- 查看 server 响应。
- 快速关闭面板，回到正在运行的页面。

### R2. 组件选择

用户必须能在发送指令之前选择或捕获一个目标 UI 组件。

第一版最低可接受实现：

- AI Vibe Panel 中可以切换“选择目标”模式。
- 复用 UME 已有能力获取 widget 信息，优先使用：
  - `ume_kit_ui` 的 `WidgetInfoInspector` / `WidgetDetailInspector` / `HitTest`
  - Flutter `WidgetInspectorService.instance.selection`
  - `ume_kit_show_code` 的 source location / source code 能力
- 用户点击运行中 App 的某个 widget，或从 UME inspector 已选择项中读取当前 selection。
- 面板收到被选中组件的 payload，包括 widget 信息、树结构、文件位置等。
- 面板在发送前展示一个简洁的目标摘要。

如果直接拦截点击和 UME 内部机制冲突，可以先和 UME 现有 inspector 配合：用户先使用 UME 的 WidgetInfo / WidgetDetail / ShowCode 选中目标，再由 AI Vibe Panel 读取当前 selection。但无论用哪种方式，选中目标都必须生成同一套上下文 payload。

### R3. 选中组件上下文

选中组件上下文在可获得时必须包含：

- 运行时 widget 类型。
- 人类可读的组件描述。
- Widget key。
- 文本 label 或 semantic label。
- 屏幕上的 bounds。
- 祖先链路。
- 子节点摘要。
- 源码文件。
- 源码行号和列号。
- 所属组件 / class，如果能获得。
- 附近源码片段或源码范围，如果能获得。

第一版允许源码位置覆盖不完整，但 schema 必须稳定，并且 UI 必须清楚展示哪些字段未知。

### R4. Server 上下文组装

Server 不能只依赖用户指令。

每次 command，server 都应该组装：

- 用户指令。
- 客户端 metadata。
- 选中组件上下文。
- 相关运行时 widget tree 摘要。
- 相关源码文件。
- 已知文件/行号附近的源码片段。
- 一个简洁的 agent prompt/context 对象。

### R5. Agent Adapter 契约

Agent adapter 必须接收结构化 context 对象，而不只是 raw instruction text。

Mock adapter 可以继续是规则型实现，但它在判断应该修改哪个文件或常量时，必须读取选中组件上下文。

### R6. Reload 反馈

Server 响应必须说明：

- 是否修改了代码。
- 修改了哪些文件。
- 是否触发了 reload。
- 如果没有自动 reload，用户下一步应该做什么。
- 简短的 agent 推理 / 输出摘要。

### R7. Server 托管 App 生命周期

为了支持可靠 hot reload，MVP 中 App 的推荐启动方式必须变为：

- 用户先启动 local AI server。
- 用户通过 server 提供的接口或命令启动 Flutter App，例如 Chrome Web / Android / iOS debug session。
- Server 持有 `flutter run` 子进程 stdin。
- Agent 修改代码后，server 发送 `r` 或 `R` 控制 hot reload / hot restart。

允许保留手动启动 App 的兼容模式，但兼容模式只能作为降级路径，不能作为主路径。

### R8. 过程通信与进度展示

AI Vibe Panel 发送指令后，必须持续展示 server 处理过程。

MVP 至少展示这些阶段：

- `queued`：请求已提交。
- `context_collected`：server 已收集组件上下文和源码上下文。
- `agent_started`：agent / Codex 开始分析。
- `patch_generated`：生成或应用了代码修改。
- `reload_started`：开始 hot reload / restart。
- `reload_failed`：reload / restart 失败。
- `self_repair_started`：server 开始自检修复编译错误。
- `self_repair_completed`：自检修复完成。
- `approval_required`：需要用户确认才能继续。
- `completed`：完成。
- `failed`：失败。

实现方式可以是 SSE、WebSocket 或短轮询。MVP 优先选择简单可靠的 SSE 或短轮询。

### R9. Codex Adapter 主路径

Server 已经有 Codex adapter 对接点，后续实现应把它视作真实 agent 主路径：

- mock adapter 只用于演示和 fallback。
- Codex adapter 必须接收结构化 `AgentContext`。
- Codex 执行过程、stdout/stderr、关键阶段事件需要透传到 App 端面板。
- 如果 Codex 不可用，server 应明确降级到 mock adapter，并把降级原因展示给用户。

### R10. Human in the Loop 简单确认

MVP 必须支持简单 Human in the loop。

需要用户确认的场景：

- 修改 `pubspec.yaml`、`pubspec.lock` 或引入/删除 pub 依赖。
- 修改平台工程配置导致需要重新编译 App，例如 Android/iOS/macOS/web 配置文件。
- Hot reload / hot restart 无法应用，需要完整重新编译或重启 debug session。
- Server 安全策略判定为 `needs_review`，但不是直接 `blocked`。
- 自动自检修复失败，需要用户决定是否继续、回滚或重试。

App 面板至少支持：

- 展示确认原因。
- 展示受影响文件。
- 展示 server 建议动作。
- 用户选择 `approved`、`rejected`、`revise`。

远期复杂修改可支持更完整的 App 端确认：

- Agent 先生成修改计划。
- App 端展示计划 / diff / 风险。
- 用户确认后 server 才应用 patch。
- 用户也可以拒绝、要求重试或补充指令。

MVP 不要求完整 diff 审批 UI，但数据契约必须支持 `requiresApproval`、`approvalRequest`、`approvalDecision`。

### R11. 单会话历史持久化

Hot restart 后，App 端 AI 面板必须恢复当前会话历史。

MVP 要求：

- 只支持一个当前会话，不需要多会话列表。
- 用户指令、server 过程事件、最终结果必须进入会话历史。
- 历史应由 server 端持久保存，App 端可做本地缓存。
- App 启动或 hot restart 后，AI 面板应从 server 拉取当前会话历史。
- 如果 server 不可用，App 可展示本地最后缓存的历史，并提示 server disconnected。

### R12. Server 安全控制

Server 必须严格限制 App 指令能造成的影响范围。

MVP 必须具备：

- 只允许修改配置的 Flutter 项目目录内文件。
- 默认禁止访问或修改项目目录外文件。
- 禁止执行危险 shell 操作，例如删除目录、重置 git、修改系统配置、安装未知脚本、访问敏感路径。
- Agent 生成的改动必须先落在受控 patch 流程中，由 server 检查后再写入。
- 限制可修改文件类型，MVP 优先允许 `.dart`、必要配置文件和本项目 server 文件。
- 限制单次修改文件数量和 patch 大小。
- 对命令执行设置超时。
- 写入前保留备份或至少记录可回滚 diff。
- 如果指令被判定为高风险，server 必须拒绝执行并向 App 面板返回清晰原因。

安全控制是 server 责任，不能信任 App 端输入。

### R13. Reload/Restart 编译错误自检修复

如果 hot reload 或 hot restart 出现编译错误，server 必须尝试自检修复。

MVP 要求：

- Server 捕获 Flutter reload/restart 输出中的编译错误。
- Server 将错误日志、相关文件、最近 patch 和上下文交给 agent。
- Agent 生成修复 patch。
- 修复 patch 仍然必须经过安全检查。
- 修复后 server 再尝试 hot reload / hot restart。
- 自检修复需要有最大次数限制，MVP 默认最多 1 次。
- 如果自检修复失败，App 面板必须展示错误摘要，并进入简单 HITL，让用户选择重试、回滚或停止。

如果变更涉及 pub 依赖、平台配置或其他需要完整重新编译 App 的内容，server 不应静默重编译，而应进入 HITL，提示用户确认。

## 验收标准

### AC1. 薄指令链路仍然可用

发送 `把按钮改成绿色，并把文案改成 Start` 仍然可以通过 mock adapter 更新 demo 按钮。

### AC2. 选中 widget 链路可用

用户可以在运行中的 App 里选中 `Hello Button` / `Start` 按钮，并在 AI Vibe Panel 里看到选中目标摘要。

### AC3. 请求包含上下文

选中按钮后发送指令时，`/command` 收到的请求必须包含：

- `instruction`
- `clientMeta`
- `selection`
- `runtimeContext`

这些字段中至少有一个必须能识别出被选中的是一个按钮类 widget，并且包含它当前显示的 label。

### AC4. 尝试获取源码位置

如果当前 Flutter debug 运行模式暴露 source location，选中组件上下文应该包含源码位置。

如果源码位置不可用，payload 必须包含：

- `sourceLocation.status = "unavailable"`
- `sourceLocation.reason`

### AC5. Server 日志可调试

Server 日志必须展示：

- 收到的指令。
- 选中 widget 摘要。
- 选中组件源码位置状态。
- 读取了哪些文件。
- 修改了哪些文件。
- reload 结果。

### AC6. App 由 Server 启动并可 Reload

用户可以通过 server-managed 模式启动 Flutter App。

当 agent 修改代码后，server 可以控制 debug session 触发 hot reload / hot restart，App 端面板能看到 reload 过程和结果。

### AC7. 过程事件可见

发送指令后，AI Vibe Panel 必须能看到至少 4 个阶段事件：

- 请求已收到。
- 上下文已收集。
- agent 正在处理。
- reload 或完成结果。

### AC8. Hot Restart 后会话历史可见

当 App 发生 hot restart 后，重新打开 AI Vibe Panel，用户仍能看到当前单会话历史，包括之前的用户指令、server 处理事件和最终结果。

### AC9. 高风险指令被阻断

当用户输入可能导致严重破坏的指令时，server 必须拒绝执行，并在 App 面板显示拒绝原因。

示例：

- 删除项目目录。
- 清空用户主目录。
- 执行 `rm -rf`、`git reset --hard` 等 destructive 操作。
- 修改项目目录外的文件。
- 下载并执行未知脚本。

### AC10. 编译错误可自检修复

当 reload/restart 因 Dart 编译错误失败时，server 至少尝试一次自动修复。修复过程必须出现在 App 面板事件流中。

### AC11. 依赖变更触发 HITL

当 agent 修改 pub 依赖或导致需要完整重新编译 App 时，server 必须暂停自动执行，向 App 面板发送 `approval_required`，由用户确认后再继续。

## 设计原则

快速 vibe coding 只能发生在稳定 spec 边界内。

核心边界是：

> Agent 基于用户意图 + 明确 UI 目标上下文修改代码，而不是基于裸 prompt 猜测代码。
