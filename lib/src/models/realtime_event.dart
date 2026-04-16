class FastRelayRealtimeEvent {
  FastRelayRealtimeEvent({
    required this.type,
    required this.feedId,
    required this.eventId,
    required this.createdAt,
    required this.data,
    this.seq,
  });

  final String type;
  final String feedId;
  final String eventId;
  final int? seq;
  final DateTime createdAt;
  final Map<String, dynamic> data;

  factory FastRelayRealtimeEvent.fromJson(Map<String, dynamic> json) {
    final createdAtText = json['createdAt']?.toString();
    final createdAt = createdAtText == null
        ? DateTime.now().toUtc()
        : DateTime.tryParse(createdAtText)?.toUtc() ?? DateTime.now().toUtc();

    final data = json['data'];
    return FastRelayRealtimeEvent(
      type: json['type']?.toString() ?? '',
      feedId: json['feedId']?.toString() ?? '',
      eventId: json['eventId']?.toString() ?? '',
      seq: _parseInt(json['seq']),
      createdAt: createdAt,
      data: _toStringDynamicMap(data),
    );
  }

  static int? _parseInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  static Map<String, dynamic> _toStringDynamicMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }
    if (value is Map) {
      return value.map((key, entryValue) => MapEntry('$key', entryValue));
    }
    return const {};
  }
}

enum FastRelayConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

class FastRelayRealtimeError {
  FastRelayRealtimeError({
    required this.code,
    required this.message,
    this.retryable = false,
    this.closeCode,
    this.details,
    this.hint,
    this.cause,
    this.stackTrace,
  });

  final String code;
  final String message;
  final bool retryable;
  final int? closeCode;
  final Object? details;
  final String? hint;
  final Object? cause;
  final StackTrace? stackTrace;
}
