import 'dart:convert';

import 'package:fastrelay_feed_sdk/fastrelay_feed_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class CaptureClient extends http.BaseClient {
  CaptureClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _handler(request);
  }
}

http.StreamedResponse jsonResponse(
  Object? body, {
  int status = 200,
  Map<String, String> headers = const {},
}) {
  final payload = body == null ? '' : jsonEncode(body);
  return http.StreamedResponse(
    Stream<List<int>>.value(utf8.encode(payload)),
    status,
    headers: {'content-type': 'application/json', ...headers},
  );
}

Map<String, dynamic> conversationJson({
  String id = 'conv_1',
  bool withMembers = false,
  bool withLastMessage = false,
}) {
  return {
    'id': id,
    'kind': 'group',
    'type': 'messaging',
    'name': 'Team',
    'custom': {'topic': 'launch'},
    'presenceEnabled': true,
    'frozen': false,
    'createdBy': 'john',
    'lastMessageSeq': 42,
    'lastMessageAt': '2026-11-02T10:00:00Z',
    'memberCount': 2,
    if (withMembers)
      'members': [
        {
          'userId': 'john',
          'user': {
            'id': 'john',
            'displayName': 'John Doe',
            'createdAt': '2026-01-01T00:00:00Z',
            'updatedAt': '2026-01-01T00:00:00Z',
          },
          'role': 'owner',
          'joinedAt': '2026-11-01T09:00:00Z',
          'lastReadSeq': 40,
          'lastReadAt': '2026-11-02T09:59:00Z',
          'online': true,
        },
        {
          'userId': 'jane',
          'role': 'member',
          'joinedAt': '2026-11-01T09:05:00Z',
          'restriction': 'muted',
          'restrictionExpiresAt': '2026-12-01T00:00:00Z',
        },
      ],
    'unreadCount': 2,
    if (withLastMessage) 'lastMessage': messageJson(seq: 42),
    'createdAt': '2026-11-01T09:00:00Z',
    'updatedAt': '2026-11-02T10:00:00Z',
  };
}

Map<String, dynamic> messageJson({String id = 'msg_1', int seq = 1}) {
  return {
    'id': id,
    'conversationId': 'conv_1',
    'seq': seq,
    'type': 'regular',
    'silent': false,
    'userId': 'john',
    'text': 'hello',
    'custom': {},
    'createdAt': '2026-11-02T10:00:00Z',
    'updatedAt': '2026-11-02T10:00:00Z',
  };
}

FastRelayClient buildClient(
  Future<http.StreamedResponse> Function(http.BaseRequest request) handler,
) {
  return FastRelayClient(
    apiKey: 'key_123',
    token: 'jwt_123',
    baseUrl: 'https://api.fastrelay.io',
    httpClient: CaptureClient(handler),
  );
}

Object? bodyOf(http.BaseRequest request) {
  final body = (request as http.Request).body;
  return body.isEmpty ? null : jsonDecode(body);
}

void main() {
  group('chat client methods', () {
    test('createConversation posts payload and parses 201 response', () async {
      late http.BaseRequest captured;
      final client = buildClient((request) async {
        captured = request;
        return jsonResponse(conversationJson(withMembers: true), status: 201);
      });

      final conversation = await client.createConversation(
        type: 'messaging',
        members: ['jane'],
        name: 'Team',
        custom: {'topic': 'launch'},
        presenceEnabled: true,
      );

      expect(captured.method, 'POST');
      expect(
        captured.url.toString(),
        'https://api.fastrelay.io/v1/conversations',
      );
      expect(captured.headers['authorization'], 'Bearer jwt_123');
      expect(bodyOf(captured), {
        'type': 'messaging',
        'members': ['jane'],
        'name': 'Team',
        'custom': {'topic': 'launch'},
        'presenceEnabled': true,
      });
      expect(conversation.id, 'conv_1');
      expect(conversation.isGroup, isTrue);
      expect(conversation.members, hasLength(2));
    });

    test('createConversation sends kind for direct conversations', () async {
      late http.BaseRequest captured;
      final client = buildClient((request) async {
        captured = request;
        return jsonResponse(conversationJson());
      });

      await client.createConversation(kind: 'direct', members: ['jane']);

      expect(bodyOf(captured), {
        'kind': 'direct',
        'members': ['jane'],
      });
    });

    test('queryConversations sends filter and parses cursor page', () async {
      late http.BaseRequest captured;
      final client = buildClient((request) async {
        captured = request;
        return jsonResponse({
          'data': [conversationJson(withLastMessage: true)],
          'nextCursor': 'cur_2',
          'hasMore': true,
        });
      });

      final page = await client.queryConversations(
        filter: const FastRelayConversationFilter(
          kind: 'group',
          members: ['jane'],
          custom: {'topic': 'launch'},
          hasUnread: true,
        ),
        sort: 'unreadCount',
        direction: 'desc',
        limit: 10,
        cursor: 'cur_1',
      );

      expect(captured.method, 'POST');
      expect(
        captured.url.toString(),
        'https://api.fastrelay.io/v1/conversations/query',
      );
      expect(bodyOf(captured), {
        'filter': {
          'kind': 'group',
          'members': ['jane'],
          'custom': {'topic': 'launch'},
          'hasUnread': true,
        },
        'sort': 'unreadCount',
        'direction': 'desc',
        'limit': 10,
        'cursor': 'cur_1',
      });
      expect(page.data.single.lastMessage?.seq, 42);
      expect(page.nextCursor, 'cur_2');
      expect(page.hasMore, isTrue);
    });

    test('queryConversations without options sends an empty body', () async {
      late http.BaseRequest captured;
      final client = buildClient((request) async {
        captured = request;
        return jsonResponse({'data': [], 'hasMore': false});
      });

      final page = await client.queryConversations();

      expect(bodyOf(captured), <String, dynamic>{});
      expect(page.data, isEmpty);
    });

    test('listMessages serializes cursor, direction, around and limit', () async {
      final captured = <http.BaseRequest>[];
      final client = buildClient((request) async {
        captured.add(request);
        return jsonResponse({
          'data': [messageJson(seq: 9), messageJson(id: 'msg_2', seq: 10)],
          'nextCursor': '9',
          'hasMore': true,
        });
      });

      final page = await client.listMessages(
        'conv_1',
        cursor: '11',
        direction: 'older',
        limit: 2,
      );
      await client.listMessages('conv_1', around: 50, limit: 20);
      await client.listMessages('conv_1', direction: 'newer');

      expect(captured[0].method, 'GET');
      expect(
        captured[0].url.toString(),
        'https://api.fastrelay.io/v1/conversations/conv_1/messages?cursor=11&direction=older&limit=2',
      );
      expect(
        captured[1].url.toString(),
        'https://api.fastrelay.io/v1/conversations/conv_1/messages?around=50&limit=20',
      );
      expect(
        captured[2].url.toString(),
        'https://api.fastrelay.io/v1/conversations/conv_1/messages?direction=newer',
      );
      expect(page.data.map((m) => m.seq), [9, 10]);
      expect(page.nextCursor, '9');
    });

    test('sendMessage posts payload with idempotency key header', () async {
      late http.BaseRequest captured;
      final client = buildClient((request) async {
        captured = request;
        return jsonResponse(messageJson(), status: 201);
      });

      final message = await client.sendMessage(
        'conv_1',
        text: 'hello',
        custom: {'kind': 'note'},
        replyToId: 'msg_0',
        silent: true,
        options: const FastRelayRequestOptions(idempotencyKey: 'idem_1'),
      );

      expect(captured.method, 'POST');
      expect(
        captured.url.toString(),
        'https://api.fastrelay.io/v1/conversations/conv_1/messages',
      );
      expect(captured.headers['idempotency-key'], 'idem_1');
      expect(bodyOf(captured), {
        'text': 'hello',
        'custom': {'kind': 'note'},
        'replyToId': 'msg_0',
        'silent': true,
      });
      expect(message.id, 'msg_1');
      expect(message.text, 'hello');
    });

    test('markConversationRead sends seq or no body for latest', () async {
      final captured = <http.BaseRequest>[];
      final client = buildClient((request) async {
        captured.add(request);
        return jsonResponse({'totalUnread': 3, 'unreadConversations': 1});
      });

      final totals = await client.markConversationRead('conv_1', seq: 12);
      await client.markConversationRead('conv_1');

      expect(captured[0].method, 'POST');
      expect(
        captured[0].url.toString(),
        'https://api.fastrelay.io/v1/conversations/conv_1/read',
      );
      expect(bodyOf(captured[0]), {'seq': 12});
      expect(bodyOf(captured[1]), isNull);
      expect(totals.totalUnread, 3);
      expect(totals.unreadConversations, 1);
    });

    test('syncChat posts anchor and parses the sync payload', () async {
      late http.BaseRequest captured;
      final client = buildClient((request) async {
        captured = request;
        return jsonResponse({
          'serverTime': '2026-11-04T12:00:00.123456Z',
          'conversations': [conversationJson()],
          'messages': [messageJson(seq: 43)],
          'removedConversationIds': ['conv_gone'],
          'reloadConversationIds': ['conv_busy'],
          'reloadAll': false,
          'unread': {'totalUnread': 5, 'unreadConversations': 2},
        });
      });

      final sync = await client.syncChat(
        since: DateTime.utc(2026, 11, 4, 11, 0, 0),
        conversationIds: ['conv_1', 'conv_gone'],
      );

      expect(captured.method, 'POST');
      expect(captured.url.toString(), 'https://api.fastrelay.io/v1/chat/sync');
      expect(bodyOf(captured), {
        'since': '2026-11-04T11:00:00.000Z',
        'conversationIds': ['conv_1', 'conv_gone'],
      });
      expect(sync.serverTime, DateTime.utc(2026, 11, 4, 12, 0, 0, 123, 456));
      expect(sync.conversations.single.id, 'conv_1');
      expect(sync.messages.single.seq, 43);
      expect(sync.removedConversationIds, ['conv_gone']);
      expect(sync.reloadConversationIds, ['conv_busy']);
      expect(sync.reloadAll, isFalse);
      expect(sync.unread.totalUnread, 5);
    });

    test('member update and remove hit member paths', () async {
      final captured = <http.BaseRequest>[];
      final client = buildClient((request) async {
        captured.add(request);
        if (request.method == 'DELETE') {
          return jsonResponse(null, status: 204);
        }
        return jsonResponse({
          'userId': 'jane',
          'role': 'moderator',
          'joinedAt': '2026-11-01T09:05:00Z',
          'restriction': 'muted',
          'restrictionExpiresAt': '2026-12-01T00:00:00Z',
        });
      });

      final member = await client.updateConversationMember(
        'conv_1',
        'jane',
        role: 'moderator',
        restriction: 'muted',
        restrictionExpiresAt: DateTime.utc(2026, 12, 1),
      );
      await client.removeConversationMember('conv_1', 'jane');

      expect(captured[0].method, 'PATCH');
      expect(
        captured[0].url.toString(),
        'https://api.fastrelay.io/v1/conversations/conv_1/members/jane',
      );
      expect(bodyOf(captured[0]), {
        'role': 'moderator',
        'restriction': 'muted',
        'restrictionExpiresAt': '2026-12-01T00:00:00.000Z',
      });
      expect(member.role, 'moderator');
      expect(member.restriction, 'muted');

      expect(captured[1].method, 'DELETE');
      expect(
        captured[1].url.toString(),
        'https://api.fastrelay.io/v1/conversations/conv_1/members/jane',
      );
    });

    test('remaining chat endpoints use expected method, path and body', () async {
      final captured = <http.BaseRequest>[];
      final client = buildClient((request) async {
        captured.add(request);
        final path = request.url.path;
        if (request.method == 'DELETE') {
          return jsonResponse(null, status: 204);
        }
        if (path.endsWith('/members') && request.method == 'GET') {
          return jsonResponse({
            'data': [
              {
                'userId': 'john',
                'role': 'owner',
                'joinedAt': '2026-11-01T09:00:00Z',
              },
            ],
            'hasMore': false,
          });
        }
        if (path.startsWith('/v1/messages/')) {
          return jsonResponse(messageJson());
        }
        if (path == '/v1/chat/unread') {
          return jsonResponse({'totalUnread': 7, 'unreadConversations': 3});
        }
        return jsonResponse(conversationJson());
      });

      await client.getConversation('conv_1');
      await client.updateConversation('conv_1', name: 'Renamed', frozen: true);
      await client.deleteConversation('conv_1');
      await client.truncateConversation('conv_1');
      await client.truncateConversation('conv_1', systemMessage: false);
      final members = await client.listConversationMembers(
        'conv_1',
        limit: 50,
        cursor: 'c1',
      );
      await client.addConversationMembers('conv_1', ['amy', 'bob']);
      await client.updateMessage('msg_1', text: 'edited');
      await client.deleteMessage('msg_1');
      final unread = await client.getUnreadTotals();

      final calls = captured
          .map(
            (r) =>
                '${r.method} ${r.url.path}${r.url.hasQuery ? '?${r.url.query}' : ''}',
          )
          .toList();
      expect(calls, [
        'GET /v1/conversations/conv_1',
        'PATCH /v1/conversations/conv_1',
        'DELETE /v1/conversations/conv_1',
        'POST /v1/conversations/conv_1/truncate',
        'POST /v1/conversations/conv_1/truncate',
        'GET /v1/conversations/conv_1/members?limit=50&cursor=c1',
        'POST /v1/conversations/conv_1/members',
        'PATCH /v1/messages/msg_1',
        'DELETE /v1/messages/msg_1',
        'GET /v1/chat/unread',
      ]);
      expect(bodyOf(captured[1]), {'name': 'Renamed', 'frozen': true});
      expect(bodyOf(captured[3]), isNull);
      expect(bodyOf(captured[4]), {'systemMessage': false});
      expect(bodyOf(captured[6]), {
        'userIds': ['amy', 'bob'],
      });
      expect(bodyOf(captured[7]), {'text': 'edited'});
      expect(members.data.single.role, 'owner');
      expect(unread.totalUnread, 7);
    });

    test('blocking uses mute type block and messages can be flagged', () async {
      final captured = <http.BaseRequest>[];
      final client = buildClient((request) async {
        captured.add(request);
        if (request.url.path.startsWith('/v1/moderation/flags')) {
          return jsonResponse({
            'id': 'flag_1',
            'reporterId': 'john',
            'targetType': 'message',
            'targetId': 'msg_1',
            'reason': 'spam',
            'createdAt': '2026-11-02T10:00:00Z',
          });
        }
        if (request.method == 'GET') {
          return jsonResponse({'data': [], 'hasMore': false});
        }
        if (request.method == 'DELETE') {
          return jsonResponse(null, status: 204);
        }
        return jsonResponse({
          'id': 'mute_1',
          'mutedUserId': 'jane',
          'type': 'block',
          'createdAt': '2026-11-02T10:00:00Z',
        });
      });

      final block = await client.createMute('jane', type: 'block');
      await client.listMutes(type: 'block');
      await client.removeMute('jane', type: 'block');
      final flag = await client.createFlag('message', 'msg_1', reason: 'spam');

      expect(bodyOf(captured[0]), {'userId': 'jane', 'type': 'block'});
      expect(captured[1].url.query, 'type=block');
      expect(captured[2].url.query, 'type=block');
      expect(bodyOf(captured[3]), {
        'targetType': 'message',
        'targetId': 'msg_1',
        'reason': 'spam',
      });
      expect(block.type, 'block');
      expect(flag.targetType, 'message');
    });

    test('namespaced chat APIs delegate to typed methods', () async {
      final captured = <String>[];
      final client = buildClient((request) async {
        captured.add('${request.method} ${request.url.path}');
        final path = request.url.path;
        if (path.endsWith('/messages') || path.startsWith('/v1/messages')) {
          return request.method == 'GET'
              ? jsonResponse({'data': [], 'hasMore': false})
              : jsonResponse(messageJson());
        }
        if (path == '/v1/chat/sync') {
          return jsonResponse({'serverTime': '2026-11-04T12:00:00Z'});
        }
        if (path.endsWith('/read') || path == '/v1/chat/unread') {
          return jsonResponse({'totalUnread': 0, 'unreadConversations': 0});
        }
        if (path.endsWith('/query')) {
          return jsonResponse({'data': [], 'hasMore': false});
        }
        return jsonResponse(conversationJson());
      });

      await client.conversations.create(members: ['jane']);
      await client.conversations.query();
      await client.conversations.markRead('conv_1');
      await client.messages.send('conv_1', text: 'hi');
      await client.messages.list('conv_1');
      await client.chat.getUnreadTotals();
      final sync = await client.chat.sync(since: DateTime.utc(2026, 11, 4));

      expect(captured, [
        'POST /v1/conversations',
        'POST /v1/conversations/query',
        'POST /v1/conversations/conv_1/read',
        'POST /v1/conversations/conv_1/messages',
        'GET /v1/conversations/conv_1/messages',
        'GET /v1/chat/unread',
        'POST /v1/chat/sync',
      ]);
      expect(sync.conversations, isEmpty);
      expect(sync.unread.totalUnread, 0);
    });
  });

  group('chat models', () {
    test('conversation parses members and lastMessage', () {
      final conversation = FastRelayConversation.fromJson(
        conversationJson(withMembers: true, withLastMessage: true),
      );

      expect(conversation.kind, 'group');
      expect(conversation.type, 'messaging');
      expect(conversation.custom, {'topic': 'launch'});
      expect(conversation.presenceEnabled, isTrue);
      expect(conversation.lastMessageSeq, 42);
      expect(conversation.lastMessageAt, DateTime.utc(2026, 11, 2, 10));
      expect(conversation.memberCount, 2);
      expect(conversation.unreadCount, 2);
      expect(conversation.lastMessage?.text, 'hello');

      final owner = conversation.members!.first;
      expect(owner.userId, 'john');
      expect(owner.user?.displayName, 'John Doe');
      expect(owner.role, 'owner');
      expect(owner.lastReadSeq, 40);
      expect(owner.online, isTrue);

      final muted = conversation.members!.last;
      expect(muted.user, isNull);
      expect(muted.restriction, 'muted');
      expect(muted.restrictionExpiresAt, DateTime.utc(2026, 12, 1));
      expect(muted.online, isNull);
    });

    test('message parses replyTo preview', () {
      final message = FastRelayMessage.fromJson({
        ...messageJson(id: 'msg_5', seq: 5),
        'replyToId': 'msg_2',
        'replyTo': {
          'id': 'msg_2',
          'seq': 2,
          'userId': 'jane',
          'text': 'original',
          'deleted': false,
        },
        'editedAt': '2026-11-02T10:05:00Z',
      });

      expect(message.replyToId, 'msg_2');
      expect(message.replyTo?.seq, 2);
      expect(message.replyTo?.userId, 'jane');
      expect(message.replyTo?.text, 'original');
      expect(message.replyTo?.deleted, isFalse);
      expect(message.isEdited, isTrue);
      expect(message.isDeleted, isFalse);
    });

    test('system message parses with null userId and text', () {
      final message = FastRelayMessage.fromJson({
        'id': 'msg_sys',
        'conversationId': 'conv_1',
        'seq': 3,
        'type': 'system',
        'silent': true,
        'custom': {
          'event': 'member.added',
          'actorId': 'john',
          'userIds': ['jane'],
        },
        'createdAt': '2026-11-02T10:00:00Z',
        'updatedAt': '2026-11-02T10:00:00Z',
      });

      expect(message.isSystem, isTrue);
      expect(message.userId, isNull);
      expect(message.text, isNull);
      expect(message.custom['event'], 'member.added');
      expect(message.custom['userIds'], ['jane']);
    });

    test('payloads with omitted nullable fields decode', () {
      final conversation = FastRelayConversation.fromJson({
        'id': 'conv_min',
        'kind': 'direct',
        'type': 'messaging',
        'custom': {},
        'presenceEnabled': false,
        'frozen': false,
        'lastMessageSeq': 0,
        'memberCount': 2,
        'createdAt': '2026-11-01T09:00:00Z',
        'updatedAt': '2026-11-01T09:00:00Z',
        'someFutureField': 'ignored',
      });
      final member = FastRelayConversationMember.fromJson({
        'userId': 'jane',
        'role': 'member',
        'joinedAt': '2026-11-01T09:00:00Z',
      });
      final deleted = FastRelayMessage.fromJson({
        'id': 'msg_d',
        'conversationId': 'conv_min',
        'seq': 1,
        'type': 'regular',
        'silent': false,
        'userId': 'jane',
        'custom': {},
        'replyToId': 'msg_x',
        'deletedAt': '2026-11-02T00:00:00Z',
        'createdAt': '2026-11-01T09:00:00Z',
        'updatedAt': '2026-11-02T00:00:00Z',
      });

      expect(conversation.isDirect, isTrue);
      expect(conversation.name, isNull);
      expect(conversation.image, isNull);
      expect(conversation.createdBy, isNull);
      expect(conversation.lastMessageAt, isNull);
      expect(conversation.truncatedSeq, isNull);
      expect(conversation.members, isNull);
      expect(conversation.unreadCount, isNull);
      expect(conversation.lastMessage, isNull);

      expect(member.user, isNull);
      expect(member.restriction, isNull);
      expect(member.lastDeliveredSeq, isNull);
      expect(member.lastReadAt, isNull);
      expect(member.online, isNull);
      expect(member.lastActiveAt, isNull);

      expect(deleted.text, isNull);
      expect(deleted.replyTo, isNull);
      expect(deleted.isDeleted, isTrue);
    });

    test('chat event typed accessors decode payloads', () {
      final receipt = FastRelayChatEvent.fromJson({
        'type': 'receipt.read',
        'conversationId': 'conv_1',
        'eventId': 'evt_1',
        'createdAt': '2026-11-02T10:00:00Z',
        'data': {
          'userId': 'jane',
          'lastReadSeq': 12,
          'lastReadAt': '2026-11-02T10:00:00Z',
        },
      });
      final added = FastRelayChatEvent.fromJson({
        'type': 'member.added',
        'conversationId': 'conv_1',
        'eventId': 'evt_2',
        'createdAt': '2026-11-02T10:00:00Z',
        'data': {
          'conversation': conversationJson(),
          'userIds': ['amy', 'bob'],
        },
      });
      final unread = FastRelayChatEvent.fromJson({
        'type': 'unread.updated',
        'eventId': 'evt_3',
        'createdAt': '2026-11-02T10:00:00Z',
        'data': {
          'totals': {'totalUnread': 4, 'unreadConversations': 2},
        },
      });

      expect(receipt.userId, 'jane');
      expect(receipt.lastReadSeq, 12);
      expect(receipt.lastReadAt, DateTime.utc(2026, 11, 2, 10));
      expect(receipt.lastDeliveredSeq, isNull);
      expect(added.conversation?.id, 'conv_1');
      expect(added.conversation?.members, isNull);
      expect(added.userIds, ['amy', 'bob']);
      expect(unread.conversationId, isNull);
      expect(unread.totals?.totalUnread, 4);
      expect(unread.message, isNull);
    });

    test('chat event with malformed typed payload returns null', () {
      final event = FastRelayChatEvent.fromJson({
        'type': 'message.new',
        'conversationId': 'conv_1',
        'eventId': 'evt_bad',
        'createdAt': 'not-a-date',
        'data': {'message': 'oops', 'userIds': 'nope', 'online': 'yes'},
      });

      expect(event.message, isNull);
      expect(event.userIds, isEmpty);
      expect(event.online, isNull);
      expect(event.data['message'], 'oops');
    });
  });
}
