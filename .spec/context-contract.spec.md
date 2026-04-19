# 上下文契约规格

## 接口

### 健康检查

```http
GET /health
```

### 启动 Flutter App

```http
POST /app/start
Content-Type: application/json
```

Server 必须支持启动或接管 Flutter debug session。MVP 推荐由 server 启动 `flutter run`，因为这样 server 才能控制 hot reload。

请求：

```ts
type StartAppRequest = {
  projectPath?: string;
  target: 'chrome' | 'android' | 'ios' | 'macos';
  deviceId?: string;
  mode?: 'debug';
};
```

响应：

```ts
type StartAppResponse = {
  success: boolean;
  appSessionId?: string;
  message: string;
  launchUrl?: string;
  logs?: string[];
};
```

### 发送修改指令

```http
POST /command
Content-Type: application/json
```

### 订阅过程事件

MVP 推荐使用 SSE：

```http
GET /command/:commandId/events
Accept: text/event-stream
```

如果 SSE 在某端不可用，可以降级为短轮询：

```http
GET /command/:commandId/status
```

### 获取当前单会话历史

```http
GET /session/current
```

Hot restart 后，App 端 AI 面板通过该接口恢复当前会话历史。

响应：

```ts
type CurrentSessionResponse = {
  success: boolean;
  session: SessionState;
};
```

## 请求结构

```ts
type CommandRequest = {
  instruction: string;
  projectPath?: string;
  appSessionId?: string;
  sessionId?: string;
  clientMeta: ClientMeta;
  selection?: SelectedComponentContext;
  runtimeContext?: RuntimeContext;
  conversation?: ConversationContext;
  approvalDecision?: ApprovalDecision;
};
```

说明：

- `instruction`：用户输入的自然语言修改指令。
- `projectPath`：可选。Flutter 项目路径；通常由 server 默认配置。
- `appSessionId`：server-managed Flutter App session ID。用于定位由 server 启动的 `flutter run` 子进程。
- `sessionId`：当前单会话 ID。MVP 只有一个当前会话，但仍保留该字段方便恢复历史。
- `clientMeta`：客户端基础信息。
- `selection`：用户选中的 UI 组件上下文。
- `runtimeContext`：当前运行时页面、屏幕和 widget tree 摘要。
- `conversation`：未来多轮对话上下文，MVP 可为空。
- `approvalDecision`：Human in the loop 远期预留，MVP 可为空。

## ClientMeta

```ts
type ClientMeta = {
  platform: 'flutter';
  appName: string;
  appVersion?: string;
  runtimeTarget?: 'web' | 'android' | 'ios' | 'macos' | 'unknown';
  debugMode?: boolean;
  umePluginVersion?: string;
  serverUrl?: string;
  appLaunchMode?: 'server-managed' | 'manual';
};
```

字段说明：

- `platform`：当前固定为 `flutter`。
- `appName`：App 名称，例如 `mobile_vibe_demo`。
- `runtimeTarget`：当前运行目标，例如 `web`、`android`、`ios`。
- `debugMode`：是否 debug 模式。
- `umePluginVersion`：AI Vibe Panel 插件版本，方便排查兼容性。
- `serverUrl`：当前使用的 server URL。
- `appLaunchMode`：App 是由 server 启动，还是用户手动启动。主路径必须是 `server-managed`。

## SelectedComponentContext

```ts
type SelectedComponentContext = {
  selectionId: string;
  capturedAt: string;
  source: 'tap-select' | 'tree-picker' | 'manual' | 'unknown';
  confidence: 'high' | 'medium' | 'low';
  widget: WidgetRuntimeDescriptor;
  sourceLocation: SourceLocation;
  codeContext?: CodeContextHint;
};
```

字段说明：

- `selectionId`：一次选择的唯一 ID。
- `capturedAt`：选择发生时间。
- `source`：选择来源。
  - `tap-select`：用户在运行 UI 上直接点击选择。
  - `tree-picker`：用户从 UME inspector / widget tree picker 中选择。
  - `manual`：手动指定。
  - `unknown`：未知来源。
- `confidence`：当前上下文对真实目标的置信度。
- `widget`：运行时 widget 描述。
- `sourceLocation`：源码位置，可能不可用。
- `codeContext`：候选文件、候选 symbol、源码片段等提示。

## WidgetRuntimeDescriptor

```ts
type WidgetRuntimeDescriptor = {
  widgetType: string;
  elementType?: string;
  renderObjectType?: string;
  key?: string;
  text?: string;
  semanticLabel?: string;
  tooltip?: string;
  enabled?: boolean;
  bounds?: Rect;
  depth?: number;
  ancestorChain: WidgetNodeSummary[];
  children: WidgetNodeSummary[];
  diagnostics?: Record<string, unknown>;
  umeInspector?: UmeInspectorContext;
};

type WidgetNodeSummary = {
  widgetType: string;
  key?: string;
  text?: string;
  semanticLabel?: string;
  sourceLocation?: SourceLocation;
};

type Rect = {
  left: number;
  top: number;
  width: number;
  height: number;
};

type UmeInspectorContext = {
  sourcePlugin?: 'WidgetInfoInspector' | 'WidgetDetailInspector' | 'ShowCode' | 'HitTest' | 'unknown';
  inspectorSelectionId?: string;
  rawSummary?: Record<string, unknown>;
};
```

字段说明：

- `widgetType`：例如 `FilledButton`、`Text`、`Scaffold`。
- `elementType`：Flutter Element 类型。
- `renderObjectType`：RenderObject 类型。
- `key`：Widget key。如果是显式 key，这是 MVP 中最可靠的 source mapping anchor。
- `text`：组件上可见文本。
- `semanticLabel`：语义 label。
- `tooltip`：tooltip 文案。
- `enabled`：组件是否可交互。
- `bounds`：组件在屏幕上的位置和尺寸。
- `depth`：在 widget tree 中的大致深度。
- `ancestorChain`：祖先链路摘要。
- `children`：子节点摘要。
- `diagnostics`：Flutter diagnostics 的原始或裁剪信息。
- `umeInspector`：来自 UME 现有 inspector 能力的上下文来源说明。后续实现必须优先复用 UME 已有插件能力，而不是从零自研 inspector。

## SourceLocation

```ts
type SourceLocation =
  | {
      status: 'available';
      file: string;
      line: number;
      column?: number;
      package?: string;
      className?: string;
      methodName?: string;
    }
  | {
      status: 'unavailable';
      reason: string;
    };
```

字段说明：

- `status = "available"`：源码位置可用。
- `file`：源码文件，例如 `lib/home_page.dart`。
- `line` / `column`：行号 / 列号。
- `className`：所属 class，例如 `HomePage`。
- `methodName`：所属方法，例如 `build`。
- `status = "unavailable"`：源码位置不可用。
- `reason`：不可用原因，例如 Web debug 未暴露、只能定位到 framework widget 等。

## CodeContextHint

```ts
type CodeContextHint = {
  candidateFiles: string[];
  candidateSymbols?: string[];
  snippet?: {
    file: string;
    startLine: number;
    endLine: number;
    content: string;
  };
};
```

字段说明：

- `candidateFiles`：server 应优先读取/分析的候选文件。
- `candidateSymbols`：候选变量、class、method、key 等 symbol。
- `snippet`：可选源码片段，用于帮助 agent 聚焦。

## RuntimeContext

```ts
type RuntimeContext = {
  currentRoute?: string;
  screenSize?: {
    width: number;
    height: number;
    devicePixelRatio?: number;
  };
  widgetTree?: WidgetTreeSnapshot;
};

type WidgetTreeSnapshot = {
  mode: 'selected-subtree' | 'screen-summary' | 'full-tree';
  maxDepth: number;
  root: WidgetTreeNode;
};

type WidgetTreeNode = WidgetNodeSummary & {
  children?: WidgetTreeNode[];
};
```

字段说明：

- `currentRoute`：当前路由。
- `screenSize`：屏幕尺寸和像素比。
- `widgetTree`：widget tree 快照。
- `mode`：
  - `selected-subtree`：只包含选中组件附近的子树。
  - `screen-summary`：当前屏幕摘要。
  - `full-tree`：完整树，MVP 不强求。
- `maxDepth`：tree 展开深度，避免 payload 过大。

## ConversationContext

```ts
type ConversationContext = {
  sessionId?: string;
  turnId?: string;
  previousTurns?: Array<{
    role: 'user' | 'agent' | 'system';
    text: string;
    createdAt?: string;
  }>;
};
```

说明：

- 多轮对话上下文预留。
- MVP 可以不发送或只发送当前 turn。

## Human in the Loop 预留

```ts
type ApprovalDecision = {
  approvalId: string;
  decision: 'approved' | 'rejected' | 'revise';
  comment?: string;
};

type ApprovalRequest = {
  approvalId: string;
  title: string;
  summary: string;
  changedFiles: string[];
  diffPreview?: string;
  risks?: string[];
};
```

MVP 不实现完整确认流，但响应和事件可以预留是否需要确认。

## 单会话历史

```ts
type SessionState = {
  sessionId: string;
  createdAt: string;
  updatedAt: string;
  turns: SessionTurn[];
};

type SessionTurn = {
  turnId: string;
  commandId?: string;
  userInstruction: string;
  selectionSummary?: string;
  events: CommandEvent[];
  finalResponse?: CommandResponse;
  createdAt: string;
  updatedAt: string;
};
```

要求：

- MVP 只维护一个当前会话。
- Server 端是会话历史的事实源。
- App 端可以缓存最近一次 `SessionState`，用于 server 暂时不可用时展示。
- Hot restart 后，App 必须通过 `GET /session/current` 拉取历史并恢复面板内容。

## 安全控制结果

```ts
type SafetyDecision = {
  allowed: boolean;
  level: 'safe' | 'needs_review' | 'blocked';
  reasons: string[];
  blockedOperations?: string[];
};
```

Server 在执行 agent 或写入 patch 前必须进行安全检查。对于 MVP：

- `safe`：允许继续。
- `needs_review`：远期 Human in the loop 使用；MVP 可直接拒绝或降级为 blocked。
- `blocked`：拒绝执行。

## 响应结构

```ts
type CommandResponse = {
  success: boolean;
  commandId?: string;
  message: string;
  applied: boolean;
  reloadTriggered: boolean;
  reloadMessage?: string;
  changedFiles: string[];
  agentOutput: string;
  contextSummary?: {
    selectedWidget?: string;
    selectedText?: string;
    sourceLocationStatus?: 'available' | 'unavailable' | 'missing';
    candidateFiles: string[];
  };
  diagnostics?: Array<{
    level: 'info' | 'warning' | 'error';
    message: string;
  }>;
  requiresApproval?: boolean;
  approvalRequest?: ApprovalRequest;
  safety?: SafetyDecision;
};
```

字段说明：

- `success`：server 是否成功处理请求。
- `commandId`：本次 command ID，用于订阅过程事件或查询状态。
- `message`：面向用户的简短结果。
- `applied`：是否实际修改代码。
- `reloadTriggered`：是否触发 reload。
- `reloadMessage`：reload 结果或用户下一步动作。
- `changedFiles`：修改文件列表。
- `agentOutput`：agent 输出摘要。
- `contextSummary`：server 对本次上下文的理解摘要。
- `diagnostics`：警告、错误、补充说明。
- `requiresApproval` / `approvalRequest`：Human in the loop 远期预留。
- `safety`：server 安全检查结果。

## 过程事件结构

```ts
type CommandEvent = {
  commandId: string;
  sequence: number;
  stage:
    | 'queued'
    | 'context_collected'
    | 'safety_checked'
    | 'safety_blocked'
    | 'agent_started'
    | 'agent_log'
    | 'patch_generated'
    | 'patch_applied'
    | 'reload_started'
    | 'reload_completed'
    | 'approval_required'
    | 'completed'
    | 'failed';
  message: string;
  timestamp: string;
  payload?: Record<string, unknown>;
};
```

AI Vibe Panel 必须展示这些事件，让用户看到处理过程，而不是等待一个最终响应。

## 请求示例

```json
{
  "instruction": "把这个按钮改成绿色，并把文案改成 Start",
  "appSessionId": "app_chrome_001",
  "sessionId": "current",
  "clientMeta": {
    "platform": "flutter",
    "appName": "mobile_vibe_demo",
    "runtimeTarget": "web",
    "debugMode": true,
    "serverUrl": "http://192.168.11.169:8787",
    "appLaunchMode": "server-managed"
  },
  "selection": {
    "selectionId": "sel_20260419_001",
    "capturedAt": "2026-04-19T12:00:00.000Z",
    "source": "tap-select",
    "confidence": "high",
    "widget": {
      "widgetType": "FilledButton",
      "elementType": "StatefulElement",
      "renderObjectType": "RenderSemanticsAnnotations",
      "text": "Hello Button",
      "enabled": true,
      "bounds": {
        "left": 132,
        "top": 326,
        "width": 156,
        "height": 48
      },
      "depth": 12,
      "ancestorChain": [
        { "widgetType": "MaterialApp" },
        {
          "widgetType": "HomePage",
          "sourceLocation": {
            "status": "available",
            "file": "lib/home_page.dart",
            "line": 8
          }
        },
        { "widgetType": "Scaffold" },
        { "widgetType": "Column" }
      ],
      "children": [
        { "widgetType": "Text", "text": "Hello Button" }
      ],
      "umeInspector": {
        "sourcePlugin": "WidgetInfoInspector",
        "inspectorSelectionId": "inspector_selected_001"
      }
    },
    "sourceLocation": {
      "status": "available",
      "file": "lib/home_page.dart",
      "line": 28,
      "column": 15,
      "className": "HomePage",
      "methodName": "build"
    },
    "codeContext": {
      "candidateFiles": ["lib/home_page.dart"],
      "candidateSymbols": ["homeButtonLabel", "homeButtonColor", "HomePage"]
    }
  },
  "runtimeContext": {
    "currentRoute": "/",
    "screenSize": {
      "width": 420,
      "height": 860,
      "devicePixelRatio": 2
    },
    "widgetTree": {
      "mode": "selected-subtree",
      "maxDepth": 3,
      "root": {
        "widgetType": "FilledButton",
        "text": "Hello Button",
        "children": [
          { "widgetType": "Text", "text": "Hello Button" }
        ]
      }
    }
  }
}
```

## 兼容规则

迁移期间，server 必须继续接受旧的薄请求结构：

```json
{
  "instruction": "...",
  "clientMeta": {
    "platform": "flutter",
    "appName": "mobile_vibe_demo"
  }
}
```

如果 `selection` 缺失，server 必须记录 `selection: missing`，并使用 fallback 文件/上下文发现逻辑。
