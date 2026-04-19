// Mirrors `ApprovalRequest` / `ApprovalDecision` from the server context
// contract. Used to drive the simple Human-in-the-loop flow required by
// `.spec/context-contract.spec.md`.

class ApprovalRequest {
  const ApprovalRequest({
    required this.approvalId,
    required this.commandId,
    required this.reason,
    required this.title,
    required this.summary,
    this.changedFiles = const [],
    this.diffPreview,
    this.risks = const [],
    this.suggestedActions = const [],
  });

  final String approvalId;
  final String commandId;

  /// One of:
  /// `dependency_change` | `requires_full_rebuild` | `self_repair_failed`
  /// | `safety_needs_review` | `user_confirmation`.
  final String reason;

  final String title;
  final String summary;
  final List<String> changedFiles;
  final String? diffPreview;
  final List<String> risks;

  /// Entries from:
  /// `continue` | `rebuild` | `rollback` | `retry` | `stop`.
  final List<String> suggestedActions;

  factory ApprovalRequest.fromJson(Map<String, dynamic> json) {
    return ApprovalRequest(
      approvalId: (json['approvalId'] as String?) ?? '',
      commandId: (json['commandId'] as String?) ?? '',
      reason: (json['reason'] as String?) ?? 'user_confirmation',
      title: (json['title'] as String?) ?? 'Approval required',
      summary: (json['summary'] as String?) ?? '',
      changedFiles: (json['changedFiles'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      diffPreview: json['diffPreview'] as String?,
      risks:
          (json['risks'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      suggestedActions: (json['suggestedActions'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'approvalId': approvalId,
        'commandId': commandId,
        'reason': reason,
        'title': title,
        'summary': summary,
        'changedFiles': changedFiles,
        if (diffPreview != null) 'diffPreview': diffPreview,
        'risks': risks,
        'suggestedActions': suggestedActions,
      };
}

class ApprovalDecision {
  const ApprovalDecision({
    required this.approvalId,
    required this.decision,
    this.comment,
  });

  final String approvalId;

  /// One of: `approved` | `rejected` | `revise`.
  final String decision;
  final String? comment;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'approvalId': approvalId,
        'decision': decision,
        if (comment != null && comment!.isNotEmpty) 'comment': comment,
      };
}
