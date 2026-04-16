class FastRelayReaction {
  const FastRelayReaction({
    required this.id,
    required this.activityId,
    required this.userId,
    required this.type,
    required this.createdAt,
  });

  final String id;
  final String activityId;
  final String userId;
  final String type;
  final DateTime createdAt;

  factory FastRelayReaction.fromJson(Map<String, dynamic> json) {
    return FastRelayReaction(
      id: json['id']?.toString() ?? '',
      activityId: json['activityId']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
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
      'type': type,
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
