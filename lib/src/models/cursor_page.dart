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

    return CursorPage<T>(
      data: _mapEntries(entries, fromJsonT),
      nextCursor: json['nextCursor']?.toString(),
      hasMore: _readBool(json['hasMore']) ?? false,
      pinned: _mapEntries(pinnedEntries, fromJsonT),
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

class NotificationGroup<T> {
  const NotificationGroup({
    required this.groupKey,
    required this.activities,
    required this.activityCount,
    this.createdAt,
    this.updatedAt,
  });

  final String groupKey;
  final List<T> activities;
  final int activityCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory NotificationGroup.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJsonT,
  ) {
    final rawActivities = json['activities'];
    final entries = rawActivities is List ? rawActivities : const [];
    final activities = _mapEntries(entries, fromJsonT);
    return NotificationGroup<T>(
      groupKey: json['groupKey']?.toString() ?? '',
      activities: activities,
      activityCount: _readInt(json['activityCount']) ?? activities.length,
      createdAt: _parseDateTime(json['createdAt']),
      updatedAt: _parseDateTime(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson(Object? Function(T value) toJsonT) {
    return {
      'groupKey': groupKey,
      'activities': activities.map(toJsonT).toList(),
      'activityCount': activityCount,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
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
    this.groups = const [],
  });

  final int unseenCount;
  final int unreadCount;
  final List<NotificationGroup<T>> groups;

  bool get isAggregated => groups.isNotEmpty;

  factory NotificationPage.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJsonT,
  ) {
    final hasDataKey = json['data'] is List;
    final hasGroupsKey = json['groups'] is List;

    if (!hasDataKey && !hasGroupsKey) {
      throw StateError(
        'NotificationPage response is missing both `data` and `groups`. '
        'Server contract violation: notification feeds must return one of them.',
      );
    }

    final groups = hasGroupsKey
        ? (json['groups'] as List)
              .whereType<Map>()
              .map(
                (entry) => NotificationGroup<T>.fromJson(
                  entry.map((key, value) => MapEntry(key.toString(), value)),
                  fromJsonT,
                ),
              )
              .toList()
        : const <Never>[];

    final basePage = hasDataKey
        ? CursorPage<T>.fromJson(json, fromJsonT)
        : CursorPage<T>(
            data: [for (final g in groups) ...g.activities],
            nextCursor: json['nextCursor']?.toString(),
            hasMore: _readBool(json['hasMore']) ?? false,
          );

    return NotificationPage<T>(
      data: basePage.data,
      nextCursor: basePage.nextCursor,
      hasMore: basePage.hasMore,
      unseenCount: _readInt(json['unseenCount']) ?? 0,
      unreadCount: _readInt(json['unreadCount']) ?? 0,
      groups: List<NotificationGroup<T>>.from(groups),
    );
  }

  @override
  Map<String, dynamic> toJson(Object? Function(T value) toJsonT) {
    return {
      ...super.toJson(toJsonT),
      'unseenCount': unseenCount,
      'unreadCount': unreadCount,
      'groups': groups.map((g) => g.toJson(toJsonT)).toList(),
    };
  }
}

List<T> _mapEntries<T>(
  Iterable raw,
  T Function(Map<String, dynamic>) fromJsonT,
) => raw
    .whereType<Map>()
    .map(
      (entry) => fromJsonT(
        entry.map((key, value) => MapEntry(key.toString(), value)),
      ),
    )
    .toList();

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

DateTime? _parseDateTime(dynamic value) {
  if (value is DateTime) {
    return value;
  }
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}
