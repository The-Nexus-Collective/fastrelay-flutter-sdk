/// A chat message.
///
/// System messages (`type == 'system'`) have no [userId] or [text]; their
/// [custom] carries `{event, actorId, userIds}`.
class FastrelayMessage {
  const FastrelayMessage({
    required this.id,
    required this.conversationId,
    required this.seq,
    this.type = 'regular',
    this.silent = false,
    this.userId,
    this.text,
    this.custom = const {},
    this.replyToId,
    this.replyTo,
    this.reactions = const {},
    this.reactionCounts = const {},
    this.editedAt,
    this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String conversationId;

  /// Per-conversation sequence number, ascending in send order.
  final int seq;

  /// `'regular'` or `'system'`.
  final String type;
  final bool silent;

  /// Author id. `null` for system messages.
  final String? userId;

  /// Message text. `null` for system messages and deleted messages.
  final String? text;
  final Map<String, dynamic> custom;
  final String? replyToId;

  /// Preview of the message this one replies to, when [replyToId] is set.
  final FastrelayReplyPreview? replyTo;

  /// Reaction type to the ids of the first 100 users who added it, in the
  /// order they reacted. Page the rest with `listMessageReactionUsers` when
  /// [reactionCounts] is higher.
  final Map<String, List<String>> reactions;

  /// Reaction type to the total number of users who added it.
  final Map<String, int> reactionCounts;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isSystem => type == 'system';
  bool get isEdited => editedAt != null;
  bool get isDeleted => deletedAt != null;

  factory FastrelayMessage.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now().toUtc();

    return FastrelayMessage(
      id: json['id']?.toString() ?? '',
      conversationId: json['conversationId']?.toString() ?? '',
      seq: _readInt(json['seq']) ?? 0,
      type: json['type']?.toString() ?? 'regular',
      silent: _readBool(json['silent']) ?? false,
      userId: json['userId']?.toString(),
      text: json['text']?.toString(),
      custom: _asMap(json['custom']),
      replyToId: json['replyToId']?.toString(),
      replyTo: json['replyTo'] is Map
          ? FastrelayReplyPreview.fromJson(_asMap(json['replyTo']))
          : null,
      reactions: _readReactions(json['reactions']),
      reactionCounts: _readReactionCounts(json['reactionCounts']),
      editedAt: _parseDateTime(json['editedAt']),
      deletedAt: _parseDateTime(json['deletedAt']),
      createdAt: _parseDateTime(json['createdAt']) ?? now,
      updatedAt: _parseDateTime(json['updatedAt']) ?? now,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversationId': conversationId,
      'seq': seq,
      'type': type,
      'silent': silent,
      'userId': userId,
      'text': text,
      'custom': custom,
      'replyToId': replyToId,
      'replyTo': replyTo?.toJson(),
      'reactions': reactions,
      'reactionCounts': reactionCounts,
      'editedAt': editedAt?.toIso8601String(),
      'deletedAt': deletedAt?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

/// Compact preview of a replied-to message embedded in [FastrelayMessage].
class FastrelayReplyPreview {
  const FastrelayReplyPreview({
    required this.id,
    this.seq,
    this.userId,
    this.text,
    this.deleted = false,
  });

  final String id;
  final int? seq;
  final String? userId;
  final String? text;
  final bool deleted;

  factory FastrelayReplyPreview.fromJson(Map<String, dynamic> json) {
    return FastrelayReplyPreview(
      id: json['id']?.toString() ?? '',
      seq: _readInt(json['seq']),
      userId: json['userId']?.toString(),
      text: json['text']?.toString(),
      deleted: _readBool(json['deleted']) ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'seq': seq,
      'userId': userId,
      'text': text,
      'deleted': deleted,
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

Map<String, List<String>> _readReactions(dynamic value) {
  if (value is! Map) {
    return const {};
  }
  return value.map(
    (type, users) => MapEntry(
      type.toString(),
      users is List
          ? users.map((userId) => userId.toString()).toList()
          : const <String>[],
    ),
  );
}

Map<String, int> _readReactionCounts(dynamic value) {
  if (value is! Map) {
    return const {};
  }
  return value.map(
    (type, count) => MapEntry(type.toString(), _readInt(count) ?? 0),
  );
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

DateTime? _parseDateTime(dynamic value) {
  if (value is DateTime) {
    return value;
  }
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}
