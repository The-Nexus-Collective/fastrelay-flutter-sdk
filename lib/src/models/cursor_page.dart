class CursorPage<T> {
  const CursorPage({
    required this.data,
    this.nextCursor,
    this.hasMore = false,
    this.pinned = const [],
  });

  final List<T> data;
  final String? nextCursor;
  final bool hasMore;
  final List<T> pinned;

  factory CursorPage.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJsonT,
  ) {
    final rawData = json['data'];
    final entries = rawData is List ? rawData : const [];
    final rawPinned = json['pinned'];
    final pinnedEntries = rawPinned is List ? rawPinned : const [];

    List<T> mapEntries(Iterable raw) => raw
        .whereType<Map>()
        .map(
          (entry) => fromJsonT(
            entry.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList();

    return CursorPage<T>(
      data: mapEntries(entries),
      nextCursor: json['nextCursor']?.toString(),
      hasMore: _readBool(json['hasMore']) ?? false,
      pinned: mapEntries(pinnedEntries),
    );
  }

  Map<String, dynamic> toJson(Object? Function(T value) toJsonT) {
    return {
      'data': data.map(toJsonT).toList(),
      'nextCursor': nextCursor,
      'hasMore': hasMore,
      'pinned': pinned.map(toJsonT).toList(),
    };
  }
}

class NotificationPage<T> extends CursorPage<T> {
  const NotificationPage({
    required super.data,
    super.nextCursor,
    super.hasMore,
    this.unseenCount = 0,
    this.unreadCount = 0,
  });

  final int unseenCount;
  final int unreadCount;

  factory NotificationPage.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJsonT,
  ) {
    final basePage = CursorPage<T>.fromJson(json, fromJsonT);

    return NotificationPage<T>(
      data: basePage.data,
      nextCursor: basePage.nextCursor,
      hasMore: basePage.hasMore,
      unseenCount: _readInt(json['unseenCount']) ?? 0,
      unreadCount: _readInt(json['unreadCount']) ?? 0,
    );
  }

  @override
  Map<String, dynamic> toJson(Object? Function(T value) toJsonT) {
    return {
      ...super.toJson(toJsonT),
      'unseenCount': unseenCount,
      'unreadCount': unreadCount,
    };
  }
}

int? _readInt(dynamic value) {
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

bool? _readBool(dynamic value) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    final normalized = value.toLowerCase();
    if (normalized == 'true') {
      return true;
    }
    if (normalized == 'false') {
      return false;
    }
  }
  return null;
}
