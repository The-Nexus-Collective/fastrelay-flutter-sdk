import 'chat_sync.dart';
import 'conversation.dart';
import 'message.dart';

/// Chat event type names delivered on `FastRelayRealtime.chatEvents`.
abstract final class FastRelayChatEventType {
  static const messageNew = 'message.new';
  static const messageUpdated = 'message.updated';
  static const messageDeleted = 'message.deleted';
  static const conversationUpdated = 'conversation.updated';
  static const conversationTruncated = 'conversation.truncated';
  static const conversationDeleted = 'conversation.deleted';
  static const memberAdded = 'member.added';
  static const memberRemoved = 'member.removed';
  static const memberUpdated = 'member.updated';
  static const receiptDelivered = 'receipt.delivered';
  static const receiptRead = 'receipt.read';
  static const typingStart = 'typing.start';
  static const typingStop = 'typing.stop';
  static const presenceChanged = 'presence.changed';
  static const unreadUpdated = 'unread.updated';
}

/// A realtime chat event. Unlike feed events it carries no `feedId`.
///
/// The raw payload is always available in [data]; the typed accessors decode
/// the parts relevant to [type] and return `null` when absent or malformed.
/// Unknown event types are delivered too, with [data] only.
class FastRelayChatEvent {
  FastRelayChatEvent({
    required this.type,
    this.conversationId,
    required this.eventId,
    required this.createdAt,
    this.data = const {},
  });

  final String type;

  /// `null` for user-scoped events (`presence.changed`, `unread.updated`).
  final String? conversationId;
  final String eventId;
  final DateTime createdAt;
  final Map<String, dynamic> data;

  /// `message.new`, `message.updated`, `message.deleted`.
  late final FastRelayMessage? message = _decode(
    'message',
    FastRelayMessage.fromJson,
  );

  /// `conversation.updated`, `conversation.truncated`, `member.added`.
  /// Realtime conversations never include `members`.
  late final FastRelayConversation? conversation = _decode(
    'conversation',
    FastRelayConversation.fromJson,
  );

  /// `member.updated`.
  late final FastRelayConversationMember? member = _decode(
    'member',
    FastRelayConversationMember.fromJson,
  );

  /// `unread.updated`.
  late final FastRelayUnreadTotals? totals = _decode(
    'totals',
    FastRelayUnreadTotals.fromJson,
  );

  /// `member.removed`, `receipt.*`, `typing.*`, `presence.changed`.
  String? get userId => data['userId']?.toString();

  /// `member.added`: the users that joined.
  List<String> get userIds {
    final raw = data['userIds'];
    if (raw is! List) {
      return const [];
    }
    return raw
        .where((entry) => entry != null)
        .map((entry) => entry.toString())
        .toList();
  }

  /// `presence.changed`.
  bool? get online {
    final value = data['online'];
    return value is bool ? value : null;
  }

  /// `presence.changed`.
  DateTime? get lastActiveAt => _parseDateTime(data['lastActiveAt']);

  /// `receipt.delivered`, `receipt.read`.
  int? get lastDeliveredSeq => _readInt(data['lastDeliveredSeq']);

  /// `receipt.delivered`, `receipt.read`.
  DateTime? get lastDeliveredAt => _parseDateTime(data['lastDeliveredAt']);

  /// `receipt.delivered`, `receipt.read`.
  int? get lastReadSeq => _readInt(data['lastReadSeq']);

  /// `receipt.delivered`, `receipt.read`.
  DateTime? get lastReadAt => _parseDateTime(data['lastReadAt']);

  factory FastRelayChatEvent.fromJson(Map<String, dynamic> json) {
    final conversationId = json['conversationId']?.toString();
    return FastRelayChatEvent(
      type: json['type']?.toString() ?? '',
      conversationId: conversationId == null || conversationId.isEmpty
          ? null
          : conversationId,
      eventId: json['eventId']?.toString() ?? '',
      createdAt:
          _parseDateTime(json['createdAt'])?.toUtc() ?? DateTime.now().toUtc(),
      data: _asMap(json['data']),
    );
  }

  T? _decode<T>(String key, T Function(Map<String, dynamic>) fromJson) {
    final raw = data[key];
    if (raw is! Map) {
      return null;
    }
    try {
      return fromJson(_asMap(raw));
    } catch (_) {
      return null;
    }
  }
}

/// The server's `connection.established` message, emitted on every
/// successful (re)connect.
///
/// Keep [serverTime] from the first connect as the `syncChat` anchor; after a
/// reconnect ([isReconnect]) call `syncChat(since: anchor)` and store the
/// response's `serverTime` as the new anchor.

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
