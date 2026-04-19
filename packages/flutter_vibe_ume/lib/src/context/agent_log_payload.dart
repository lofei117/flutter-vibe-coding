// Mirrors `AgentLogPayload` from `.spec/context-contract.spec.md`. Server is
// expected to attach this structured metadata to `agent_log` events so the
// AI Vibe Panel can highlight high-signal lines (errors, safety, approval,
// repair) instead of collapsing them silently.

class AgentLogPayload {
  const AgentLogPayload({
    this.stream,
    this.level,
    this.category,
    this.chunkIndex,
    this.truncated,
    this.source,
  });

  /// `stdout` | `stderr` | `system` | `codex`.
  final String? stream;

  /// `debug` | `info` | `warning` | `error`.
  final String? level;

  /// `thinking` | `context` | `patch` | `safety` | `reload` | `repair` |
  /// `approval` | `fallback` | `raw`.
  final String? category;

  final int? chunkIndex;
  final bool? truncated;

  /// `codex` | `mock` | `flutter` | `server` | `shell`.
  final String? source;

  /// True when this entry must remain visible even after the surrounding
  /// `agent_log` group is collapsed (per spec §过程事件颗粒度契约).
  bool get isHighSignal {
    if (level == 'error') return true;
    final c = category;
    if (c == null) return false;
    return c == 'safety' || c == 'approval' || c == 'repair' || c == 'fallback';
  }

  static AgentLogPayload? maybe(Map<String, dynamic>? raw) {
    if (raw == null) return null;
    String? str(String key) {
      final v = raw[key];
      return v is String && v.isNotEmpty ? v : null;
    }

    int? intOf(String key) {
      final v = raw[key];
      if (v is num) return v.toInt();
      return null;
    }

    bool? boolOf(String key) {
      final v = raw[key];
      if (v is bool) return v;
      return null;
    }

    final stream = str('stream');
    final level = str('level');
    final category = str('category');
    final source = str('source');
    final chunkIndex = intOf('chunkIndex');
    final truncated = boolOf('truncated');

    if (stream == null &&
        level == null &&
        category == null &&
        source == null &&
        chunkIndex == null &&
        truncated == null) {
      return null;
    }

    return AgentLogPayload(
      stream: stream,
      level: level,
      category: category,
      chunkIndex: chunkIndex,
      truncated: truncated,
      source: source,
    );
  }
}
