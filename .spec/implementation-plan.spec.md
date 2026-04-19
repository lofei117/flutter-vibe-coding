# 实施计划规格

## Phase 0：保留当前可运行闭环

状态：基本完成。

在增加上下文能力时，必须保持这些行为继续可用：

- Chrome Web App 可以运行。
- UME Core 悬浮面板可以打开。
- Server URL 可以保存和重置。
- `/health` 可用。
- `/command` 接受旧的薄请求。
- Mock adapter 可以把 demo 按钮改成绿色和 `Start`。
- Codex adapter 对接点继续可用。
- App hot restart 后可以恢复当前单会话历史。
- Server 有基础安全控制，能拒绝明显危险指令。

验证方式：

```bash
cd mobile_vibe_demo
flutter --no-version-check analyze
flutter --no-version-check run -d chrome
```

## Phase 1：Server 托管 Flutter App 生命周期

目标：把 App 启动方式从“用户手动 flutter run”校准为“server-managed flutter run”。

原因：

- Hot reload 必须由 server 控制。
- Server 必须持有 `flutter run` 子进程 stdin，才能在修改代码后发送 `r` 或 `R`。
- App 端面板展示的处理进度也应该和 server 当前 command/app session 绑定。

需要新增 server 能力：

- `POST /app/start`
- `GET /app/session`
- `POST /app/:appSessionId/reload`
- `POST /app/:appSessionId/stop`

MVP 启动命令：

```bash
flutter --no-version-check run -d chrome
```

Android/iOS 后续复用同一 app session 抽象。

验证标准：

- 用户启动 server 后，可以通过 server 启动 Chrome Flutter App。
- Server 保存 `appSessionId`。
- Server 可以向该 session stdin 发送 `r` 并触发 reload。

## Phase 2：定义共享上下文类型

增加 Dart 和 TypeScript 两端镜像的 context model。

Dart model 目录：

```text
mobile_vibe_demo/lib/ume_plugins/context/
```

需要新增的 Dart 文件：

- `selected_component_context.dart`
- `widget_runtime_descriptor.dart`
- `runtime_context.dart`
- `command_payload.dart`

TypeScript 类型目录：

```text
local_ai_server/src/types/
```

需要更新的 TypeScript 类型：

- 扩展 `CommandRequest`
- 增加 `SelectedComponentContext`
- 增加 `WidgetRuntimeDescriptor`
- 增加 `RuntimeContext`
- 增加响应字段 `contextSummary`
- 增加过程事件类型 `CommandEvent`
- 增加 `appSessionId`
- 预留 Human in the loop 类型 `ApprovalRequest` / `ApprovalDecision`

验证标准：

- Dart JSON 序列化能生成规格中的示例请求结构。
- TypeScript server 在收到 selection 时能打印选中组件摘要。

## Phase 3：复用 UME 现有 Inspector 能力获取组件上下文

目标：优先复用 UME 已有能力获取 widget 信息、widget 树结构、文件位置，而不是自研 inspector。

已确认可复用能力：

- `ume_kit_ui`
  - `WidgetInfoInspector`
  - `WidgetDetailInspector`
  - `HitTest`
  - `InspectorOverlay`
- Flutter debug service
  - `WidgetInspectorService.instance.selection`
  - `InspectorSelection.current`
  - `InspectorSelection.currentElement`
  - `debugGetDiagnosticChain()`
- `ume_kit_show_code`
  - `PageInfoHelper`
  - `creationLocation.file`
  - `creationLocation.line`
  - source code 获取能力

最低路径：

1. 在 AI Vibe Panel 中增加 `Use Current UME Selection` / `Select Target`。
2. 复用 UME inspector 当前 selection。
3. 从 selection 中提取：
   - widget 描述
   - renderObject 描述
   - ancestor chain
   - source file / line
   - source snippet，如果可获得
4. 转换为 `SelectedComponentContext`。
5. 在 panel 中展示 selected widget 摘要。
6. 发送 `/command` 时包含 `selection`。

如果直接读取 UME 现有类遇到封装限制，可以先复制或适配 UME kit 内部 helper 的最小逻辑，但设计上仍视为复用 UME 能力。

## Phase 4：App 面板与 Server 过程通信

目标：用户发送指令后，AI Vibe Panel 能看到 server 处理过程。

推荐实现：

- MVP 优先 SSE：`GET /command/:commandId/events`
- 如果 Flutter Web/移动端 SSE 不稳定，则用短轮询：`GET /command/:commandId/status`

面板至少展示：

- 当前 stage。
- 最新 message。
- Codex / agent 输出摘要。
- changed files。
- reload 状态。
- 当前单会话历史。

## Phase 5：单会话历史持久化

目标：hot restart 后，App 端 AI 面板仍能看到历史会话。

范围：

- MVP 只支持一个当前会话。
- 不做多会话列表。
- Server 端保存会话历史，是事实源。
- App 端可用本地缓存做弱兜底。

需要新增 server 能力：

- `GET /session/current`
- 每次 `/command` 创建一个 `SessionTurn`
- 每个 `CommandEvent` 追加到当前 turn
- command 完成后保存 `finalResponse`

App 端要求：

- 面板初始化时拉取 `GET /session/current`
- hot restart 后自动恢复历史
- server 不可用时展示本地缓存，并提示连接状态

验证标准：

- 发送一次指令，看到过程事件和结果。
- 触发 hot restart。
- 重新打开 AI Vibe Panel，仍能看到刚才的指令、事件和结果。

## Phase 6：Server 安全控制

目标：避免 App 下发的指令造成严重甚至毁灭级操作。

Server 必须默认不信任 App 输入。

MVP 安全策略：

- 限制项目根目录：所有读写必须在 `FLUTTER_PROJECT_PATH` 内。
- 限制可写文件类型：默认允许 `.dart`，必要时允许本项目明确列出的配置文件。
- 限制 patch 范围：单次修改文件数、总 diff 大小、单文件大小都应有限制。
- 禁止危险命令：`rm -rf`、`git reset --hard`、`git clean -fdx`、`chmod -R`、`chown -R`、系统配置修改、未知脚本下载执行等。
- 禁止访问敏感路径：用户主目录、SSH key、系统目录、浏览器数据、环境密钥文件等。
- 所有 shell 命令必须走 allowlist。
- Agent 输出不能直接无审查写入文件，必须先生成 patch/result，再由 server 检查。
- 写入前记录备份或 diff，支持人工回滚。
- 命令执行必须有超时。

需要新增 server 模块：

- `safety_policy.ts`
- `patch_guard_service.ts`
- `command_allowlist.ts`

验证标准：

- 输入“删除整个项目”必须被拒绝。
- 输入“执行 rm -rf ~”必须被拒绝。
- 输入“修改项目外文件”必须被拒绝。
- 正常修改按钮文案/颜色仍然允许。

## Phase 7：源码位置解析

源码映射按以下优先级尝试：

1. UME `WidgetInfoInspector` / `WidgetDetailInspector` / `ShowCode` 已经拿到的 source location。
2. Flutter `WidgetInspectorService` 暴露的 creation location。
3. Widget key 到 source registry 的映射。
4. Server 构建的静态源码索引。
5. 退化到 candidate files 和 candidate symbols。

推荐 MVP 机制：

- 给重要 demo widget 增加显式 key：
  - `Key('home.title')`
  - `Key('home.description')`
  - `Key('home.helloButton')`
- 在 Dart 侧增加轻量 source registry：

```dart
const sourceRegistry = {
  'home.helloButton': {
    'file': 'lib/home_page.dart',
    'symbol': 'homeButtonLabel',
    'owner': 'HomePage',
  },
};
```

这不是最终的全自动方案，但它能在 MVP 中给 server 提供可靠的 file/symbol anchor。

## Phase 8：Server 上下文组装

更新 server command 流程：

1. 解析 `selection`。
2. 记录 selected widget 摘要。
3. 执行指令级安全预检查。
4. 从 selected context 中解析 candidate files。
5. 读取 selected location 附近的源码片段。
6. 构建 `AgentContext` 对象：
   - instruction
   - selected widget
   - selected source hints
   - runtime tree summary
   - file snippets
7. 把 `AgentContext` 传给 adapter，优先 Codex adapter。
8. 对 agent 结果执行 patch 安全检查。
9. 安全通过后写入文件并触发 reload。

Adapter 变化：

- Codex adapter 是真实主路径，接收结构化 `AgentContext`。
- Codex stdout/stderr 和关键进度必须转换为 `CommandEvent` 发给 App 面板。
- Mock adapter 是 fallback。
- 如果 selected widget key/text 指向 home button，修改 `homeButtonLabel` 和 `homeButtonColor`。
- 如果 selected widget 指向 title，修改 `homeTitle`。
- 如果没有 selection，保留当前 fallback 规则。

## Phase 9：Codex 主路径

目标：让当前已支持的 Codex adapter 成为主要 agent 能力。

要求：

- `AGENT_ADAPTER=codex` 时使用 Codex。
- Codex command 拼接集中在 `codex_adapter.ts`。
- Codex 接收完整 `AgentContext`。
- Codex 输出过程进入 command event stream。
- Codex 不可用时明确 fallback 到 mock，并在 App 面板展示原因。
- Codex 生成的 patch 必须经过 server 安全检查才能应用。

风险：

- Codex CLI 参数和本地安装方式可能变化。
- Codex 执行时间较长，必须有过程反馈。
- Codex 可能生成不适合热重载的改动，需要 fallback 到 hot restart。

缓解：

- 保留 mock adapter fallback。
- 保留 command event stream。
- 保留 server-managed restart 能力。

## Phase 10：Reload 集成

主路径：

- Server 启动 Flutter App。
- Server 持有 `flutter run` stdin。
- 修改代码后发送 `r`。
- 如果 hot reload 失败，发送 `R` hot restart。
- App 面板展示 reload 过程和结果。
- Hot restart 后 App 面板恢复当前单会话历史。

降级路径：

- 如果用户手动启动 App，server 返回清晰的手动 reload 指令。
- 这个模式只能作为兼容 fallback，不是推荐主路径。

## Phase 11：Human in the Loop 远期规划

未来复杂修改可支持 App 端确认：

- Codex 先生成计划或 diff。
- Server 发送 `approval_required` event。
- App 面板展示计划 / diff / 风险。
- 用户选择 approve / reject / revise。
- Server 根据用户决定继续或终止。

MVP 只保留契约，不实现完整交互。

## 重新校准后的 MVP 完成定义

满足以下全部条件，MVP 才算完成：

- 用户可以打开悬浮 AI panel。
- App 由 server-managed 模式启动。
- 用户可以复用 UME inspector selection 选中 home button。
- Panel 展示 selected target summary。
- Panel 展示 server/agent 处理过程事件。
- Hot restart 后 Panel 恢复当前单会话历史。
- `/command` 收到 selection context + instruction。
- Server 日志打印 selected widget 和 source hint。
- Server 拒绝明显危险指令，并向 App 面板展示原因。
- Codex adapter 或 mock fallback 使用 selection context 修改正确文件。
- Server 控制 App reload，并展示修改结果。

## 下一步具体行动

优先实现 Phase 1、Phase 2、Phase 3、Phase 5、Phase 6 的最小闭环。

原因：

- Server 托管 App 是 hot reload 的前置条件。
- 共享 context 类型是后续通信的前置条件。
- 复用 UME inspector 是选中组件上下文的最短路径。
- 单会话历史是 hot restart 后体验连续性的前置条件。
- Server 安全控制是允许 App 下发自然语言指令的前置条件。
