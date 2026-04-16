class FastRelayBookmark {
  const FastRelayBookmark({
    required this.id,
    required this.activityId,
    required this.userId,
    required this.createdAt,
  });

  final String id;
  final String activityId;
  final String userId;
  final DateTime createdAt;

  factory FastRelayBookmark.fromJson(Map<String, dynamic> json) {
    return FastRelayBookmark(
      id: json['id']?.toString() ?? '',
      activityId: json['activityId']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      createdAt:
          _parseDateTime(json['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'activityId': activityId,
      'userId': userId,
      'createdAt': createdAt.toIso8601String(),
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
