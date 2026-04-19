class CommandEvent {
  const CommandEvent({
    required this.commandId,
    required this.sequence,
    required this.stage,
    required this.message,
    required this.timestamp,
    this.payload,
  });

  final String commandId;
  final int sequence;

  /// One of: 'queued' | 'context_collected' | 'safety_checked' |
  /// 'safety_blocked' | 'agent_started' | 'agent_log' | 'patch_generated' |
  /// 'patch_applied' | 'reload_started' | 'reload_completed' |
  /// 'approval_required' | 'completed' | 'failed'.
  final String stage;
  final String message;
  final String timestamp;
  final Map<String, dynamic>? payload;

  bool get isTerminal =>
      stage == 'completed' || stage == 'failed' || stage == 'safety_blocked';

  Map<String, dynamic> toJson() => {
        'commandId': commandId,
        'sequence': sequence,
        'stage': stage,
        'message': message,
        'timestamp': timestamp,
        if (payload != null) 'payload': payload,
      };

  factory CommandEvent.fromJson(Map<String, dynamic> json) => CommandEvent(
        commandId: (json['commandId'] as String?) ?? '',
        sequence: (json['sequence'] as num?)?.toInt() ?? 0,
        stage: (json['stage'] as String?) ?? 'unknown',
        message: (json['message'] as String?) ?? '',
        timestamp: (json['timestamp'] as String?) ?? '',
        payload: json['payload'] is Map<String, dynamic>
            ? json['payload'] as Map<String, dynamic>
            : null,
      );
}
