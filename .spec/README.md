# Mobile Vibe Coding 规格说明

这个目录是第一次可运行 spike 之后的需求事实源。

后续开发方式应该是：先用 spec coding 明确边界，再在这个边界内用 vibe coding 快速实现。这个项目的核心需求不是“把自然语言发送给服务端”，而是：

> 通过 UME 选择或识别一个 UI 组件，收集这个组件足够的运行时上下文和源码上下文，把这些上下文连同用户指令一起发送给本地 agent server，然后由 server 修改 Flutter 工程，并形成快速反馈闭环。

## 最新校准

- 组件信息、widget 树结构、文件位置等能力应尽可能复用 UME 已有插件/kit，例如 `WidgetInfoInspector`、`WidgetDetailInspector`、`HitTest`、`ShowCode`，不要优先自研 inspector。
- Server 已经支持 Codex adapter 对接；真实 agent 主路径应逐步使用 Codex，mock 只作为 fallback。
- App 端面板必须持续展示 server / agent 处理过程，避免用户提交指令后只能等待。
- 为了支持可靠 hot reload，Flutter App 必须由 server 启动或接管，server 需要持有 `flutter run` / `flutter attach` 控制权。
- Hot restart 后，App 端必须能恢复当前单会话历史；MVP 不做多会话。
- Server 必须严格控制 App 下发指令的执行边界，避免严重或毁灭级操作。
- Reload/restart 出现编译错误时，server 必须尝试自检修复；修复失败后进入 HITL。
- 涉及 pub 依赖或完整重编译 App 的变更必须进入简单 HITL，由用户确认。
- Human in the loop 分层实现：MVP 做简单确认，完整 diff 审批放入远期规划。
- 面向产品、QA 等非工程角色时，profile/release 包走提单模式，不强依赖 debug inspector 和 hot reload。
- 本地最小 CI/CD 只验证链路：`flutter analyze`、`flutter test`、`flutter build web`、本地 preview 刷新。

## 规格文件

- [产品规格](./product.spec.md)：产品目标、非目标、用户流程、验收标准。
- [上下文契约](./context-contract.spec.md)：请求/响应结构，以及选中组件上下文 schema。
- [实施计划](./implementation-plan.spec.md)：分阶段工程计划和验证检查点。

## 当前状态快照

当前 App 发给 server 的请求体是：

```json
{
  "instruction": "把按钮改成绿色，并把文案改成 Start",
  "clientMeta": {
    "platform": "flutter",
    "appName": "flutter_vibe_app"
  }
}
```

当前 server 行为：

- 接收 `instruction`。
- 记录 `clientMeta`。
- 从磁盘读取少量固定 Flutter 文件。
- 使用 mock adapter 修改 `lib/home_page.dart`。
- 尝试触发热重载，或者提示用户手动热重载。

当前缺口：

- 没有选中 widget 的上下文。
- 没有组件描述。
- 没有源码文件名、行号、列号等信息。
- 没有运行时 widget tree 或代码树结构。
- 没有让用户明确确认本次要修改的目标组件。
- App 还不是由 server-managed session 启动，因此 hot reload 控制链路还不完整。
- App 面板还没有订阅 server 过程事件。
- Hot restart 后还不能恢复当前单会话历史。
- Server 还没有系统化安全策略和 patch guard。
- Reload/restart 编译错误还不能自动自检修复。
- pub 依赖或完整重编译类变更还没有 HITL 确认。

这些缺口不是可有可无的第二阶段优化，而是 mobile vibe coding app 真正 MVP 的基础能力。
