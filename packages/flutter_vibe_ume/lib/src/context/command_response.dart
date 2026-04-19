import 'approval.dart';

class SafetyDecision {
  const SafetyDecision({
    required this.allowed,
    required this.level,
    this.reasons = const [],
    this.blockedOperations,
  });

  final bool allowed;

  /// One of: 'safe' | 'needs_review' | 'blocked'.
  final String level;
  final List<String> reasons;
  final List<String>? blockedOperations;

  factory SafetyDecision.fromJson(Map<String, dynamic> json) => SafetyDecision(
        allowed: json['allowed'] == true,
        level: (json['level'] as String?) ?? 'unknown',
        reasons:
            (json['reasons'] as List?)?.map((e) => e.toString()).toList() ?? [],
        blockedOperations: (json['blockedOperations'] as List?)
            ?.map((e) => e.toString())
            .toList(),
      );
}

class CommandDiagnostic {
  const CommandDiagnostic({required this.level, required this.message});

  /// One of: 'info' | 'warning' | 'error'.
  final String level;
  final String message;

  factory CommandDiagnostic.fromJson(Map<String, dynamic> json) =>
      CommandDiagnostic(
        level: (json['level'] as String?) ?? 'info',
        message: (json['message'] as String?) ?? '',
      );
}

class ContextSummary {
  const ContextSummary({
    this.selectedWidget,
    this.selectedText,
    this.sourceLocationStatus,
    this.candidateFiles = const [],
  });

  final String? selectedWidget;
  final String? selectedText;

  /// One of: 'available' | 'unavailable' | 'missing'.
  final String? sourceLocationStatus;
  final List<String> candidateFiles;

  factory ContextSummary.fromJson(Map<String, dynamic> json) => ContextSummary(
        selectedWidget: json['selectedWidget'] as String?,
        selectedText: json['selectedText'] as String?,
        sourceLocationStatus: json['sourceLocationStatus'] as String?,
        candidateFiles: (json['candidateFiles'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );
}

class CommandResponse {
  const CommandResponse({
    required this.success,
    this.commandId,
    required this.message,
    required this.applied,
    required this.reloadTriggered,
    this.reloadMessage,
    this.changedFiles = const [],
    this.agentOutput = '',
    this.contextSummary,
    this.diagnostics = const [],
    this.requiresApproval,
    this.approvalRequest,
    this.safety,
    this.raw = const {},
  });

  final bool success;
  final String? commandId;
  final String message;
  final bool applied;
  final bool reloadTriggered;
  final String? reloadMessage;
  final List<String> changedFiles;
  final String agentOutput;
  final ContextSummary? contextSummary;
  final List<CommandDiagnostic> diagnostics;
  final bool? requiresApproval;
  final ApprovalRequest? approvalRequest;
  final SafetyDecision? safety;
  final Map<String, dynamic> raw;

  factory CommandResponse.fromJson(Map<String, dynamic> json) {
    return CommandResponse(
      success: json['success'] == true,
      commandId: json['commandId'] as String?,
      message: (json['message'] as String?) ?? '',
      applied: json['applied'] == true,
      reloadTriggered: json['reloadTriggered'] == true,
      reloadMessage: json['reloadMessage'] as String?,
      changedFiles: (json['changedFiles'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      agentOutput: (json['agentOutput'] as String?) ?? '',
      contextSummary: json['contextSummary'] is Map<String, dynamic>
          ? ContextSummary.fromJson(
              json['contextSummary'] as Map<String, dynamic>,
            )
          : null,
      diagnostics: (json['diagnostics'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(CommandDiagnostic.fromJson)
              .toList() ??
          const [],
      requiresApproval: json['requiresApproval'] as bool?,
      approvalRequest: json['approvalRequest'] is Map<String, dynamic>
          ? ApprovalRequest.fromJson(
              json['approvalRequest'] as Map<String, dynamic>,
            )
          : null,
      safety: json['safety'] is Map<String, dynamic>
          ? SafetyDecision.fromJson(json['safety'] as Map<String, dynamic>)
          : null,
      raw: json,
    );
  }
}
