import 'user.dart';

class FastRelayComment {
  const FastRelayComment({
    required this.id,
    required this.activityId,
    required this.userId,
    this.user,
    required this.text,
    this.parentId,
    this.mentionedUsers = const [],
    this.reactionCounts = const {},
    this.custom,
    this.score = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String activityId;
  final String userId;

  /// Author user object embedded by the server. `null` when the author has
  /// no user record or the payload was not enriched.
  final FastRelayUser? user;
  final String text;
  final String? parentId;
  final List<String> mentionedUsers;
  final Map<String, int> reactionCounts;

  /// Arbitrary custom payload attached by the server (e.g. attachments).
  final Map<String, dynamic>? custom;
  final double score;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isReply => parentId != null && parentId!.isNotEmpty;

  factory FastRelayComment.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now().toUtc();
    final reactionCounts = _asMap(
      json['reactionCounts'],
    ).map((key, value) => MapEntry(key, _readInt(value) ?? 0));
    final custom = _asMap(json['custom']);

    return FastRelayComment(
      id: json['id']?.toString() ?? '',
      activityId: json['activityId']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      user: json['user'] is Map
          ? FastRelayUser.fromJson(_asMap(json['user']))
          : null,
      text: json['text']?.toString() ?? '',
      parentId: json['parentId']?.toString(),
      mentionedUsers: _asStringList(json['mentionedUsers']),
      reactionCounts: reactionCounts,
      custom: custom.isEmpty ? null : custom,
      score: _readDouble(json['score']) ?? 0,
      createdAt: _parseDateTime(json['createdAt']) ?? now,
      updatedAt: _parseDateTime(json['updatedAt']) ?? now,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'activityId': activityId,
      'userId': userId,
      'user': user?.toJson(),
      'text': text,
      'parentId': parentId,
      'mentionedUsers': mentionedUsers,
      'reactionCounts': reactionCounts,
      'custom': custom,
      'score': score,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.from(value);
  }
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const {};
}

List<String> _asStringList(dynamic value) {
  final entries = value is List ? value : const [];
  return entries.map((entry) => entry.toString()).toList();
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

double? _readDouble(dynamic value) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
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
