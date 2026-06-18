import 'reaction.dart';

class FastRelayActivity {
  const FastRelayActivity({
    required this.id,
    required this.type,
    this.text,
    required this.userId,
    this.feeds = const [],
    this.visibility = 'public',
    this.custom,
    this.popularity = 0,
    this.reactionCounts = const {},
    this.commentCount = 0,
    this.bookmarkCount = 0,
    this.expiresAt,
    required this.createdAt,
    required this.updatedAt,
    this.ownReactions,
  });

  final String id;
  final String type;
  final String? text;
  final String userId;
  final List<String> feeds;
  final String visibility;
  final Map<String, dynamic>? custom;
  final double popularity;
  final Map<String, int> reactionCounts;
  final int commentCount;
  final int bookmarkCount;
  final DateTime? expiresAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<FastRelayReaction>? ownReactions;

  factory FastRelayActivity.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now().toUtc();
    final custom = _asMap(json['custom']);

    return FastRelayActivity(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'post',
      text: json['text']?.toString(),
      userId: json['userId']?.toString() ?? '',
      feeds: _asStringList(json['feeds']),
      visibility: json['visibility']?.toString() ?? 'public',
      custom: custom.isEmpty ? null : custom,
      popularity: _readDouble(json['popularity']) ?? 0,
      reactionCounts: _asIntMap(json['reactionCounts']),
      commentCount: _readInt(json['commentCount']) ?? 0,
      bookmarkCount: _readInt(json['bookmarkCount']) ?? 0,
      expiresAt: _parseDateTime(json['expiresAt']),
      createdAt: _parseDateTime(json['createdAt']) ?? now,
      updatedAt: _parseDateTime(json['updatedAt']) ?? now,
      ownReactions: json['ownReactions'] == null
          ? null
          : (json['ownReactions'] as List)
                .map((e) => FastRelayReaction.fromJson(_asMap(e)))
                .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'text': text,
      'userId': userId,
      'feeds': feeds,
      'visibility': visibility,
      'custom': custom,
      'popularity': popularity,
      'reactionCounts': reactionCounts,
      'commentCount': commentCount,
      'bookmarkCount': bookmarkCount,
      'expiresAt': expiresAt?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'ownReactions': ownReactions?.map((r) => r.toJson()).toList(),
    };
  }
}

List<String> _asStringList(dynamic value) {
  final entries = value is List ? value : const [];
  return entries.map((entry) => entry.toString()).toList();
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

Map<String, int> _asIntMap(dynamic value) {
  final map = _asMap(value);
  return map.map((key, item) => MapEntry(key, _readInt(item) ?? 0));
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
