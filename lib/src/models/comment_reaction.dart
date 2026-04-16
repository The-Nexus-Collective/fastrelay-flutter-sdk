class FastRelayCommentReaction {
  const FastRelayCommentReaction({
    required this.id,
    required this.commentId,
    required this.userId,
    required this.type,
    required this.createdAt,
  });

  final String id;
  final String commentId;
  final String userId;
  final String type;
  final DateTime createdAt;

  factory FastRelayCommentReaction.fromJson(Map<String, dynamic> json) {
    return FastRelayCommentReaction(
      id: json['id']?.toString() ?? '',
      commentId: json['commentId']?.toString() ?? '',
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
      'commentId': commentId,
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
