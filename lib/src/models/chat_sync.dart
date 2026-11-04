import 'conversation.dart';
import 'message.dart';

/// Unread counters across all of the user's conversations.
class FastRelayUnreadTotals {
  const FastRelayUnreadTotals({
    this.totalUnread = 0,
    this.unreadConversations = 0,
  });

  final int totalUnread;
  final int unreadConversations;

  factory FastRelayUnreadTotals.fromJson(Map<String, dynamic> json) {
    return FastRelayUnreadTotals(
      totalUnread: _readInt(json['totalUnread']) ?? 0,
      unreadConversations: _readInt(json['unreadConversations']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'totalUnread': totalUnread,
      'unreadConversations': unreadConversations,
    };
  }
}

/// Result of `syncChat`: everything that changed since the given anchor.
class FastRelayChatSync {
  const FastRelayChatSync({
    required this.serverTime,
    this.conversations = const [],
    this.messages = const [],
    this.removedConversationIds = const [],
    this.reloadConversationIds = const [],
    this.reloadAll = false,
    this.unread = const FastRelayUnreadTotals(),
  });

  /// Pass as `since` on the next sync.
  final DateTime serverTime;

  /// Conversations changed since the anchor.
  final List<FastRelayConversation> conversations;

  /// Messages created, edited or deleted since the anchor, in changed
  /// conversations not listed in [reloadConversationIds].
  final List<FastRelayMessage> messages;

  /// Requested conversations the user can no longer access.
  final List<String> removedConversationIds;

  /// Conversations with too many changes; reload their message history.
  final List<String> reloadConversationIds;

  /// Too many conversations changed; reload all conversations with
  /// `queryConversations`.
  final bool reloadAll;
  final FastRelayUnreadTotals unread;

  factory FastRelayChatSync.fromJson(Map<String, dynamic> json) {
    return FastRelayChatSync(
      serverTime: _parseDateTime(json['serverTime']) ?? DateTime.now().toUtc(),
      conversations: _mapEntries(
        json['conversations'],
        FastRelayConversation.fromJson,
      ),
      messages: _mapEntries(json['messages'], FastRelayMessage.fromJson),
      removedConversationIds: _asStringList(json['removedConversationIds']),
      reloadConversationIds: _asStringList(json['reloadConversationIds']),
      reloadAll: json['reloadAll'] == true,
      unread: json['unread'] is Map
          ? FastRelayUnreadTotals.fromJson(_asMap(json['unread']))
          : const FastRelayUnreadTotals(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'serverTime': serverTime.toIso8601String(),
      'conversations': conversations.map((entry) => entry.toJson()).toList(),
      'messages': messages.map((entry) => entry.toJson()).toList(),
      'removedConversationIds': removedConversationIds,
      'reloadConversationIds': reloadConversationIds,
      'reloadAll': reloadAll,
      'unread': unread.toJson(),
    };
  }
}

List<T> _mapEntries<T>(
  dynamic raw,
  T Function(Map<String, dynamic>) fromJsonT,
) {
  final entries = raw is List ? raw : const [];
  return entries
      .whereType<Map>()
      .map((entry) => fromJsonT(_asMap(entry)))
      .toList();
}

List<String> _asStringList(dynamic value) {
  final entries = value is List ? value : const [];
  return entries
      .where((entry) => entry != null)
      .map((entry) => entry.toString())
      .toList();
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

DateTime? _parseDateTime(dynamic value) {
  if (value is DateTime) {
    return value;
  }
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}
