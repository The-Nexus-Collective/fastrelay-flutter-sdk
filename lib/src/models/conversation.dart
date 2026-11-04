import 'message.dart';
import 'user.dart';

/// A chat conversation (direct or group).
class FastrelayConversation {
  const FastrelayConversation({
    required this.id,
    this.kind = 'group',
    required this.type,
    this.name,
    this.image,
    this.custom = const {},
    this.presenceEnabled = false,
    this.frozen = false,
    this.createdBy,
    this.lastMessageSeq = 0,
    this.lastMessageAt,
    this.truncatedSeq,
    this.truncatedAt,
    this.memberCount = 0,
    this.members,
    this.unreadCount,
    this.lastMessage,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// `'direct'` or `'group'`.
  final String kind;

  /// Conversation type configured on the app (e.g. `'messaging'`).
  final String type;
  final String? name;
  final String? image;
  final Map<String, dynamic> custom;
  final bool presenceEnabled;
  final bool frozen;
  final String? createdBy;
  final int lastMessageSeq;
  final DateTime? lastMessageAt;
  final int? truncatedSeq;
  final DateTime? truncatedAt;
  final int memberCount;

  /// The first 100 members by join time. `null` when omitted (realtime
  /// events); page through the rest with `listConversationMembers`.
  final List<FastrelayConversationMember>? members;

  /// Unread messages for the requesting user, when the server scoped the
  /// response to a user.
  final int? unreadCount;

  /// Latest message visible to the requesting user. Query results only.
  final FastrelayMessage? lastMessage;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isDirect => kind == 'direct';
  bool get isGroup => kind == 'group';

  factory FastrelayConversation.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now().toUtc();
    final rawMembers = json['members'];

    return FastrelayConversation(
      id: json['id']?.toString() ?? '',
      kind: json['kind']?.toString() ?? 'group',
      type: json['type']?.toString() ?? '',
      name: json['name']?.toString(),
      image: json['image']?.toString(),
      custom: _asMap(json['custom']),
      presenceEnabled: _readBool(json['presenceEnabled']) ?? false,
      frozen: _readBool(json['frozen']) ?? false,
      createdBy: json['createdBy']?.toString(),
      lastMessageSeq: _readInt(json['lastMessageSeq']) ?? 0,
      lastMessageAt: _parseDateTime(json['lastMessageAt']),
      truncatedSeq: _readInt(json['truncatedSeq']),
      truncatedAt: _parseDateTime(json['truncatedAt']),
      memberCount: _readInt(json['memberCount']) ?? 0,
      members: rawMembers is List
          ? rawMembers
                .whereType<Map>()
                .map(
                  (entry) =>
                      FastrelayConversationMember.fromJson(_asMap(entry)),
                )
                .toList()
          : null,
      unreadCount: _readInt(json['unreadCount']),
      lastMessage: json['lastMessage'] is Map
          ? FastrelayMessage.fromJson(_asMap(json['lastMessage']))
          : null,
      createdAt: _parseDateTime(json['createdAt']) ?? now,
      updatedAt: _parseDateTime(json['updatedAt']) ?? now,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'kind': kind,
      'type': type,
      'name': name,
      'image': image,
      'custom': custom,
      'presenceEnabled': presenceEnabled,
      'frozen': frozen,
      'createdBy': createdBy,
      'lastMessageSeq': lastMessageSeq,
      'lastMessageAt': lastMessageAt?.toIso8601String(),
      'truncatedSeq': truncatedSeq,
      'truncatedAt': truncatedAt?.toIso8601String(),
      'memberCount': memberCount,
      'members': members?.map((member) => member.toJson()).toList(),
      'unreadCount': unreadCount,
      'lastMessage': lastMessage?.toJson(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

/// A member of a [FastrelayConversation] with their read/delivery cursors.
class FastrelayConversationMember {
  const FastrelayConversationMember({
    required this.userId,
    this.user,
    this.role = 'member',
    required this.joinedAt,
    this.restriction,
    this.restrictionExpiresAt,
    this.lastDeliveredSeq,
    this.lastDeliveredAt,
    this.lastReadSeq,
    this.lastReadAt,
    this.online,
    this.lastActiveAt,
  });

  final String userId;

  /// Embedded user record. `null` when the user has no record or the payload
  /// was not enriched.
  final FastrelayUser? user;

  /// `'owner'`, `'moderator'` or `'member'`.
  final String role;
  final DateTime joinedAt;

  /// `'banned'` or `'muted'`; `null` when unrestricted.
  final String? restriction;
  final DateTime? restrictionExpiresAt;
  final int? lastDeliveredSeq;
  final DateTime? lastDeliveredAt;
  final int? lastReadSeq;
  final DateTime? lastReadAt;

  /// Presence, when the conversation has presence enabled.
  final bool? online;
  final DateTime? lastActiveAt;

  factory FastrelayConversationMember.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now().toUtc();

    return FastrelayConversationMember(
      userId: json['userId']?.toString() ?? '',
      user: json['user'] is Map
          ? FastrelayUser.fromJson(_asMap(json['user']))
          : null,
      role: json['role']?.toString() ?? 'member',
      joinedAt: _parseDateTime(json['joinedAt']) ?? now,
      restriction: json['restriction']?.toString(),
      restrictionExpiresAt: _parseDateTime(json['restrictionExpiresAt']),
      lastDeliveredSeq: _readInt(json['lastDeliveredSeq']),
      lastDeliveredAt: _parseDateTime(json['lastDeliveredAt']),
      lastReadSeq: _readInt(json['lastReadSeq']),
      lastReadAt: _parseDateTime(json['lastReadAt']),
      online: _readBool(json['online']),
      lastActiveAt: _parseDateTime(json['lastActiveAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'user': user?.toJson(),
      'role': role,
      'joinedAt': joinedAt.toIso8601String(),
      'restriction': restriction,
      'restrictionExpiresAt': restrictionExpiresAt?.toIso8601String(),
      'lastDeliveredSeq': lastDeliveredSeq,
      'lastDeliveredAt': lastDeliveredAt?.toIso8601String(),
      'lastReadSeq': lastReadSeq,
      'lastReadAt': lastReadAt?.toIso8601String(),
      'online': online,
      'lastActiveAt': lastActiveAt?.toIso8601String(),
    };
  }
}

/// Filter for `queryConversations`. Only set fields are sent.
class FastrelayConversationFilter {
  const FastrelayConversationFilter({
    this.kind,
    this.type,
    this.members,
    this.custom,
    this.frozen,
    this.hasUnread,
  });

  /// `'direct'` or `'group'`.
  final String? kind;
  final String? type;

  /// Conversations containing all of these users.
  final List<String>? members;

  /// JSON containment match against the conversation's custom data.
  final Map<String, dynamic>? custom;
  final bool? frozen;
  final bool? hasUnread;

  Map<String, dynamic> toJson() {
    return {
      if (kind != null) 'kind': kind,
      if (type != null) 'type': type,
      if (members != null) 'members': members,
      if (custom != null) 'custom': custom,
      if (frozen != null) 'frozen': frozen,
      if (hasUnread != null) 'hasUnread': hasUnread,
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
