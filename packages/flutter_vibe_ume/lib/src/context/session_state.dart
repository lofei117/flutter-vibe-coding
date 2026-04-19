import 'command_event.dart';
import 'command_response.dart';

class SessionTurn {
  const SessionTurn({
    required this.turnId,
    this.commandId,
    required this.userInstruction,
    this.selectionSummary,
    this.events = const [],
    this.finalResponse,
    required this.createdAt,
    required this.updatedAt,
  });

  final String turnId;
  final String? commandId;
  final String userInstruction;
  final String? selectionSummary;
  final List<CommandEvent> events;
  final CommandResponse? finalResponse;
  final String createdAt;
  final String updatedAt;

  factory SessionTurn.fromJson(Map<String, dynamic> json) => SessionTurn(
        turnId: (json['turnId'] as String?) ?? '',
        commandId: json['commandId'] as String?,
        userInstruction: (json['userInstruction'] as String?) ?? '',
        selectionSummary: json['selectionSummary'] as String?,
        events: (json['events'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(CommandEvent.fromJson)
                .toList() ??
            const [],
        finalResponse: json['finalResponse'] is Map<String, dynamic>
            ? CommandResponse.fromJson(
                json['finalResponse'] as Map<String, dynamic>,
              )
            : null,
        createdAt: (json['createdAt'] as String?) ?? '',
        updatedAt: (json['updatedAt'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {
        'turnId': turnId,
        if (commandId != null) 'commandId': commandId,
        'userInstruction': userInstruction,
        if (selectionSummary != null) 'selectionSummary': selectionSummary,
        'events': events.map((e) => e.toJson()).toList(),
        if (finalResponse != null) 'finalResponse': finalResponse!.raw,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
}

class SessionState {
  const SessionState({
    required this.sessionId,
    required this.createdAt,
    required this.updatedAt,
    this.turns = const [],
  });

  final String sessionId;
  final String createdAt;
  final String updatedAt;
  final List<SessionTurn> turns;

  factory SessionState.fromJson(Map<String, dynamic> json) => SessionState(
        sessionId: (json['sessionId'] as String?) ?? '',
        createdAt: (json['createdAt'] as String?) ?? '',
        updatedAt: (json['updatedAt'] as String?) ?? '',
        turns: (json['turns'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(SessionTurn.fromJson)
                .toList() ??
            const [],
      );

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'turns': turns.map((e) => e.toJson()).toList(),
      };
}
