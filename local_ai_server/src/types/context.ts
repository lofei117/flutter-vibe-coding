export type Rect = {
  left: number;
  top: number;
  width: number;
  height: number;
};

export type SourceLocation =
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

export type WidgetNodeSummary = {
  widgetType: string;
  key?: string;
  text?: string;
  semanticLabel?: string;
  sourceLocation?: SourceLocation;
};

export type UmeInspectorContext = {
  sourcePlugin?:
    | 'WidgetInfoInspector'
    | 'WidgetDetailInspector'
    | 'ShowCode'
    | 'HitTest'
    | 'unknown';
  inspectorSelectionId?: string;
  rawSummary?: Record<string, unknown>;
};

export type WidgetRuntimeDescriptor = {
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

export type CodeContextHint = {
  candidateFiles: string[];
  candidateSymbols?: string[];
  snippet?: {
    file: string;
    startLine: number;
    endLine: number;
    content: string;
  };
};

export type SelectedComponentContext = {
  selectionId: string;
  capturedAt: string;
  source: 'tap-select' | 'tree-picker' | 'manual' | 'unknown';
  confidence: 'high' | 'medium' | 'low';
  widget: WidgetRuntimeDescriptor;
  sourceLocation: SourceLocation;
  codeContext?: CodeContextHint;
};

export type WidgetTreeNode = WidgetNodeSummary & {
  children?: WidgetTreeNode[];
};

export type WidgetTreeSnapshot = {
  mode: 'selected-subtree' | 'screen-summary' | 'full-tree';
  maxDepth: number;
  root: WidgetTreeNode;
};

export type RuntimeContext = {
  currentRoute?: string;
  screenSize?: {
    width: number;
    height: number;
    devicePixelRatio?: number;
  };
  widgetTree?: WidgetTreeSnapshot;
};
