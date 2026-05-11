class FastRelayFeedActivityPin {
  const FastRelayFeedActivityPin({
    required this.appId,
    required this.feedId,
    required this.activityId,
    required this.pinnedAt,
    required this.pinnedBy,
  });

  final String appId;
  final String feedId;
  final String activityId;
  final DateTime pinnedAt;
  final String pinnedBy;

  factory FastRelayFeedActivityPin.fromJson(Map<String, dynamic> json) {
    return FastRelayFeedActivityPin(
      appId: json['appId']?.toString() ?? '',
      feedId: json['feedId']?.toString() ?? '',
      activityId: json['activityId']?.toString() ?? '',
      pinnedAt:
          _parseDateTime(json['pinnedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      pinnedBy: json['pinnedBy']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'appId': appId,
      'feedId': feedId,
      'activityId': activityId,
      'pinnedAt': pinnedAt.toIso8601String(),
      'pinnedBy': pinnedBy,
    };
  }
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
