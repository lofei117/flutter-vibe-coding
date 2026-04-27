import 'client_meta.dart';
import 'runtime_context.dart';

/// Page-level location info for a feedback ticket. In profile/release builds
/// we cannot rely on creation locations or UME inspector source links, so
/// page identity becomes the primary anchor.
class FeedbackPageContext {
  const FeedbackPageContext({this.route, this.pageId, this.title});

  final String? route;
  final String? pageId;
  final String? title;

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (route != null) 'route': route,
        if (pageId != null) 'pageId': pageId,
        if (title != null) 'title': title,
      };

  factory FeedbackPageContext.fromJson(Map<String, dynamic> json) {
    return FeedbackPageContext(
      route: json['route'] as String?,
      pageId: json['pageId'] as String?,
      title: json['title'] as String?,
    );
  }
}

class FeedbackRect {
  const FeedbackRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'left': left,
        'top': top,
        'width': width,
        'height': height,
      };
}

class FeedbackTarget {
  const FeedbackTarget({
    this.semanticId,
    this.widgetKey,
    this.text,
    this.semanticLabel,
    this.bounds,
  });

  final String? semanticId;
  final String? widgetKey;
  final String? text;
  final String? semanticLabel;
  final FeedbackRect? bounds;

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (semanticId != null) 'semanticId': semanticId,
        if (widgetKey != null) 'widgetKey': widgetKey,
        if (text != null) 'text': text,
        if (semanticLabel != null) 'semanticLabel': semanticLabel,
        if (bounds != null) 'bounds': bounds!.toJson(),
      };
}

class FeedbackScreenshot {
  const FeedbackScreenshot({
    required this.mimeType,
    this.dataBase64,
    this.localPath,
  });

  /// 'image/png' | 'image/jpeg'
  final String mimeType;
  final String? dataBase64;
  final String? localPath;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'mimeType': mimeType,
        if (dataBase64 != null) 'dataBase64': dataBase64,
        if (localPath != null) 'localPath': localPath,
      };
}

class FeedbackTicketRequest {
  const FeedbackTicketRequest({
    required this.instruction,
    required this.clientMeta,
    required this.pageContext,
    this.target,
    this.screenshot,
    this.runtimeContext,
  });

  final String instruction;
  final ClientMeta clientMeta;
  final FeedbackPageContext pageContext;
  final FeedbackTarget? target;
  final FeedbackScreenshot? screenshot;
  final RuntimeContext? runtimeContext;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'instruction': instruction,
        'clientMeta': clientMeta.toJson(),
        'pageContext': pageContext.toJson(),
        if (target != null) 'target': target!.toJson(),
        if (screenshot != null) 'screenshot': screenshot!.toJson(),
        if (runtimeContext != null) 'runtimeContext': runtimeContext!.toJson(),
      };
}

/// One step of the local CI pipeline (analyze / test / build_web / deploy).
class FeedbackCiStep {
  const FeedbackCiStep({
    required this.name,
    required this.command,
    required this.status,
    this.durationMs,
    this.exitCode,
    this.logSummary,
  });

  final String name;
  final String command;

  /// queued | running | passed | failed | skipped
  final String status;
  final int? durationMs;
  final int? exitCode;
  final String? logSummary;

  factory FeedbackCiStep.fromJson(Map<String, dynamic> json) {
    return FeedbackCiStep(
      name: json['name'] as String? ?? '',
      command: json['command'] as String? ?? '',
      status: json['status'] as String? ?? 'queued',
      durationMs: (json['durationMs'] as num?)?.toInt(),
      exitCode: (json['exitCode'] as num?)?.toInt(),
      logSummary: json['logSummary'] as String?,
    );
  }
}

class FeedbackCiResult {
  const FeedbackCiResult({
    required this.status,
    required this.steps,
  });

  /// queued | running | passed | failed
  final String status;
  final List<FeedbackCiStep> steps;

  factory FeedbackCiResult.fromJson(Map<String, dynamic> json) {
    return FeedbackCiResult(
      status: json['status'] as String? ?? 'queued',
      steps: (json['steps'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(FeedbackCiStep.fromJson)
              .toList() ??
          const [],
    );
  }
}

class FeedbackTicketEvent {
  const FeedbackTicketEvent({
    required this.ticketId,
    required this.sequence,
    required this.stage,
    required this.message,
    required this.timestamp,
    this.payload,
  });

  final String ticketId;
  final int sequence;
  final String stage;
  final String message;
  final String timestamp;
  final Map<String, dynamic>? payload;

  factory FeedbackTicketEvent.fromJson(Map<String, dynamic> json) {
    return FeedbackTicketEvent(
      ticketId: json['ticketId'] as String? ?? '',
      sequence: (json['sequence'] as num?)?.toInt() ?? 0,
      stage: json['stage'] as String? ?? 'log',
      message: json['message'] as String? ?? '',
      timestamp: json['timestamp'] as String? ?? '',
      payload: json['payload'] is Map<String, dynamic>
          ? json['payload'] as Map<String, dynamic>
          : null,
    );
  }
}

class FeedbackTicket {
  const FeedbackTicket({
    required this.ticketId,
    required this.status,
    required this.instruction,
    required this.events,
    this.changedFiles = const [],
    this.previewUrl,
    this.failureReason,
    this.ci,
    this.createdAt,
    this.updatedAt,
  });

  final String ticketId;

  /// queued | planned | applied | ci_running | deployed | failed
  final String status;
  final String instruction;
  final List<FeedbackTicketEvent> events;
  final List<String> changedFiles;
  final String? previewUrl;
  final String? failureReason;
  final FeedbackCiResult? ci;
  final String? createdAt;
  final String? updatedAt;

  bool get isTerminal => status == 'deployed' || status == 'failed';

  factory FeedbackTicket.fromJson(Map<String, dynamic> json) {
    return FeedbackTicket(
      ticketId: json['ticketId'] as String? ?? '',
      status: json['status'] as String? ?? 'queued',
      instruction: json['instruction'] as String? ?? '',
      events: (json['events'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(FeedbackTicketEvent.fromJson)
              .toList() ??
          const [],
      changedFiles: (json['changedFiles'] as List?)
              ?.whereType<String>()
              .toList() ??
          const [],
      previewUrl: json['previewUrl'] as String?,
      failureReason: json['failureReason'] as String?,
      ci: json['ci'] is Map<String, dynamic>
          ? FeedbackCiResult.fromJson(json['ci'] as Map<String, dynamic>)
          : null,
      createdAt: json['createdAt'] as String?,
      updatedAt: json['updatedAt'] as String?,
    );
  }
}
