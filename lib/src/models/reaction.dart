import 'user.dart';

class FastrelayReaction {
  const FastrelayReaction({
    required this.id,
    required this.activityId,
    required this.userId,
    this.user,
    required this.type,
    required this.createdAt,
  });

  final String id;
  final String activityId;
  final String userId;

  /// Reactor user object embedded by the server. `null` when the reactor has
  /// no user record or the payload was not enriched.
  final FastrelayUser? user;
  final String type;
  final DateTime createdAt;

  factory FastrelayReaction.fromJson(Map<String, dynamic> json) {
    return FastrelayReaction(
      id: json['id']?.toString() ?? '',
      activityId: json['activityId']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      user: json['user'] is Map
          ? FastrelayUser.fromJson(
              (json['user'] as Map).map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            )
          : null,
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
      'user': user?.toJson(),
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
