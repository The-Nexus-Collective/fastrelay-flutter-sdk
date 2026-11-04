import 'dart:async';
import 'dart:convert';

import 'package:fastrelay_feed_sdk/fastrelay_feed_sdk.dart';
import 'package:flutter/widgets.dart';
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

class FakeSocketFactory {
  final sockets = <FakeSocket>[];

  FastrelayRealtimeSocket call(Uri uri) {
    final socket = FakeSocket(uri);
    sockets.add(socket);
    return socket;
  }

  Future<void> dispose() async {
    for (final socket in sockets) {
      await socket.dispose();
    }
  }
}

class FakeSocket implements FastrelayRealtimeSocket {
  FakeSocket(this.uri);

  final Uri uri;
  final List<String> sentMessages = <String>[];

  final _messagesController = StreamController<String>.broadcast();
  final _connectionController =
      StreamController<FastrelayRealtimeSocketState>.broadcast();

  bool isClosed = false;

  @override
  Stream<FastrelayRealtimeSocketState> get connection =>
      _connectionController.stream;

  @override
  Stream<String> get messages => _messagesController.stream;

  void emitConnection(
    FastrelayRealtimeSocketStatus status, {
    int? closeCode,
    String? reason,
    Object? error,
  }) {
    if (_connectionController.isClosed) {
      return;
    }
    _connectionController.add(
      FastrelayRealtimeSocketState(
        status: status,
        closeCode: closeCode,
        reason: reason,
        error: error,
      ),
    );
  }

  void emitJson(Map<String, dynamic> payload) {
    if (_messagesController.isClosed) {
      return;
    }
    _messagesController.add(jsonEncode(payload));
  }

  List<Map<String, dynamic>> get sentJsonMessages {
    return sentMessages
        .map((item) => jsonDecode(item) as Map<String, dynamic>)
        .toList();
  }

  @override
  void close() {
    isClosed = true;
  }

  @override
  void send(String message) {
    sentMessages.add(message);
  }

  Future<void> dispose() async {
    await _messagesController.close();
    await _connectionController.close();
  }
}

FastrelayRealtime _buildRealtime(
  FastrelayClient client,
  FakeSocketFactory socketFactory, {
  FastrelayTokenProvider? tokenProvider,
  bool maintainBackgroundConnection = false,
}) {
  return FastrelayRealtime(
    client: client,
    token: client.token ?? '',
    tokenProvider: tokenProvider,
    maintainBackgroundConnection: maintainBackgroundConnection,
    socketFactory: socketFactory.call,
    subscribeDebounce: const Duration(milliseconds: 8),
    reconnectInitialDelay: const Duration(milliseconds: 1),
    reconnectMaxDelay: const Duration(milliseconds: 1),
    deadConnectionTimeout: const Duration(seconds: 30),
  );
}

Future<void> _flush([Duration duration = const Duration(milliseconds: 25)]) {
  return Future<void>.delayed(duration);
}

String _jwtExpiringAt(DateTime expiresAt) {
  String encode(Map<String, Object> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  final exp = expiresAt.millisecondsSinceEpoch ~/ 1000;
  return '${encode({'alg': 'HS256'})}.${encode({'exp': exp})}.sig';
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  group('FastrelayRealtime', () {
    test('connectUser enables realtime and derives websocket URL', () async {
      final fakeSocketFactory = FakeSocketFactory();

      final client = FastrelayClient(
        apiKey: 'key_123',
        baseUrl: 'https://api.fastrelay.io',
        httpClient: CaptureClient((_) async => jsonResponse({'ok': true})),
        realtimeFactory:
            ({
              required client,
              required token,
              tokenProvider,
              maintainBackgroundConnection = false,
              FastrelayRealtimeSocketFactory? socketFactory,
            }) {
              return FastrelayRealtime(
                client: client,
                token: token,
                tokenProvider: tokenProvider,
                maintainBackgroundConnection: maintainBackgroundConnection,
                socketFactory: fakeSocketFactory.call,
                subscribeDebounce: const Duration(milliseconds: 8),
                reconnectInitialDelay: const Duration(milliseconds: 1),
                reconnectMaxDelay: const Duration(milliseconds: 1),
              );
            },
      );

      await client.connectUser({'id': 'john'}, 'jwt_123', realtime: true);

      expect(fakeSocketFactory.sockets, hasLength(1));
      expect(
        fakeSocketFactory.sockets.first.uri.toString(),
        'wss://api.fastrelay.io/v1/realtime?token=jwt_123',
      );

      await client.realtime!.dispose();
      client.close();
      await fakeSocketFactory.dispose();
    });

    test(
      'feed.events auto-subscribes, routes events, and auto-unsubscribes',
      () async {
        final socketFactory = FakeSocketFactory();
        final client = FastrelayClient(
          apiKey: 'key_123',
          token: 'jwt_123',
          baseUrl: 'https://api.fastrelay.io',
          httpClient: CaptureClient((_) async => jsonResponse({'ok': true})),
        );

        client.realtime = _buildRealtime(client, socketFactory);
        await client.realtime!.connect();

        final socket = socketFactory.sockets.single;
        socket.emitConnection(FastrelayRealtimeSocketStatus.connected);

        final events = <FastrelayRealtimeEvent>[];
        final subscription = client
            .feed('timeline', 'john')
            .events()
            .listen(events.add);

        await _flush();

        final subscribe = socket.sentJsonMessages.firstWhere(
          (entry) => entry['type'] == 'subscribe',
        );
        expect(subscribe['feeds'], ['timeline:john']);

        socket.emitJson({
          'type': 'activity.created',
          'feedId': 'timeline:john',
          'eventId': 'evt_1',
          'createdAt': '2026-03-03T10:00:00Z',
          'data': {
            'userId': 'john',
            'reactionCounts': {'likeCount': 2},
          },
        });

        await _flush();

        expect(events, hasLength(1));
        expect(events.first.type, 'activity.created');
        expect(events.first.feedId, 'timeline:john');
        expect(events.first.data['userId'], 'john');
        expect(events.first.data['reactionCounts'], {'likeCount': 2});

        await subscription.cancel();
        await _flush();

        final unsubscribe = socket.sentJsonMessages.firstWhere(
          (entry) => entry['type'] == 'unsubscribe',
        );
        expect(unsubscribe['feeds'], ['timeline:john']);

        await client.realtime!.dispose();
        client.close();
        await socketFactory.dispose();
      },
    );

    test(
      'rapid feed.events subscriptions are batched into one subscribe',
      () async {
        final socketFactory = FakeSocketFactory();
        final client = FastrelayClient(
          apiKey: 'key_123',
          token: 'jwt_123',
          baseUrl: 'https://api.fastrelay.io',
          httpClient: CaptureClient((_) async => jsonResponse({'ok': true})),
        );

        client.realtime = _buildRealtime(client, socketFactory);
        await client.realtime!.connect();

        final socket = socketFactory.sockets.single;
        socket.emitConnection(FastrelayRealtimeSocketStatus.connected);

        final sub1 = client.feed('timeline', 'john').events().listen((_) {});
        final sub2 = client
            .feed('notification', 'john')
            .events()
            .listen((_) {});

        await _flush();

        final subscribeMessages = socket.sentJsonMessages
            .where((entry) => entry['type'] == 'subscribe')
            .toList();

        expect(subscribeMessages, hasLength(1));
        expect(
          (subscribeMessages.first['feeds'] as List).cast<String>()..sort(),
          ['notification:john', 'timeline:john'],
        );

        await sub1.cancel();
        await sub2.cancel();
        await client.realtime!.dispose();
        client.close();
        await socketFactory.dispose();
      },
    );

    test('deduplicates events by eventId', () async {
      final socketFactory = FakeSocketFactory();
      final client = FastrelayClient(
        apiKey: 'key_123',
        token: 'jwt_123',
        baseUrl: 'https://api.fastrelay.io',
        httpClient: CaptureClient((_) async => jsonResponse({'ok': true})),
      );

      client.realtime = _buildRealtime(client, socketFactory);
      await client.realtime!.connect();

      final socket = socketFactory.sockets.single;
      socket.emitConnection(FastrelayRealtimeSocketStatus.connected);

      final received = <FastrelayRealtimeEvent>[];
      final subscription = client
          .feed('timeline', 'john')
          .events()
          .listen(received.add);

      await _flush();

      final payload = {
        'type': 'activity.created',
        'feedId': 'timeline:john',
        'eventId': 'evt_dup',
        'createdAt': '2026-03-03T10:00:00Z',
        'data': {'id': 'act_1'},
      };

      socket.emitJson(payload);
      socket.emitJson(payload);

      await _flush();

      expect(received, hasLength(1));

      await subscription.cancel();
      await client.realtime!.dispose();
      client.close();
      await socketFactory.dispose();
    });

    test('reconnects and re-subscribes desired feeds', () async {
      final socketFactory = FakeSocketFactory();
      final client = FastrelayClient(
        apiKey: 'key_123',
        token: 'jwt_123',
        baseUrl: 'https://api.fastrelay.io',
        httpClient: CaptureClient((_) async => jsonResponse({'data': []})),
      );

      client.realtime = _buildRealtime(client, socketFactory);
      await client.realtime!.connect();

      final socket1 = socketFactory.sockets.single;
      socket1.emitConnection(FastrelayRealtimeSocketStatus.connected);

      final subscription = client
          .feed('timeline', 'john')
          .events()
          .listen((_) {});

      await _flush();

      socket1.emitJson({
        'type': 'subscribe.success',
        'feeds': ['timeline:john'],
      });
      socket1.emitConnection(
        FastrelayRealtimeSocketStatus.disconnected,
        closeCode: 1006,
      );

      await _flush(const Duration(milliseconds: 80));

      expect(socketFactory.sockets.length, 2);

      final socket2 = socketFactory.sockets.last;
      socket2.emitConnection(FastrelayRealtimeSocketStatus.connected);

      await _flush();

      final subscribe = socket2.sentJsonMessages.firstWhere(
        (entry) => entry['type'] == 'subscribe',
      );
      expect(subscribe['feeds'], ['timeline:john']);

      await subscription.cancel();
      await client.realtime!.dispose();
      client.close();
      await socketFactory.dispose();
    });

    test(
      'connectionEstablished flags reconnects without refetching feeds',
      () async {
        final socketFactory = FakeSocketFactory();
        final requests = <http.BaseRequest>[];
        final client = FastrelayClient(
          apiKey: 'key_123',
          token: 'jwt_123',
          baseUrl: 'https://api.fastrelay.io',
          httpClient: CaptureClient((request) async {
            requests.add(request);
            return jsonResponse({'data': []});
          }),
        );

        client.realtime = _buildRealtime(client, socketFactory);
        final established = <FastrelayConnectionEstablished>[];
        final establishedSubscription = client.realtime!.connectionEstablished
            .listen(established.add);
        final feedSubscription = client
            .feed('timeline', 'john')
            .events()
            .listen((_) {});
        await client.realtime!.connect();

        final socket1 = socketFactory.sockets.single;
        socket1.emitConnection(FastrelayRealtimeSocketStatus.connected);
        socket1.emitJson({
          'type': 'connection.established',
          'connectionId': 'conn_1',
          'serverTime': '2026-11-04T12:00:00Z',
        });
        await _flush();
        socket1.emitConnection(
          FastrelayRealtimeSocketStatus.disconnected,
          closeCode: 1006,
        );
        await _flush(const Duration(milliseconds: 80));

        final socket2 = socketFactory.sockets.last;
        socket2.emitConnection(FastrelayRealtimeSocketStatus.connected);
        socket2.emitJson({
          'type': 'connection.established',
          'connectionId': 'conn_2',
          'serverTime': '2026-11-04T12:05:00Z',
        });
        await _flush();

        expect(established.map((e) => e.connectionId), ['conn_1', 'conn_2']);
        expect(established.map((e) => e.isReconnect), [false, true]);
        expect(established.last.serverTime, DateTime.utc(2026, 11, 4, 12, 5));
        expect(requests, isEmpty);

        await establishedSubscription.cancel();
        await feedSubscription.cancel();
        await client.realtime!.dispose();
        client.close();
        await socketFactory.dispose();
      },
    );

    test(
      '4003 triggers tokenProvider refresh and reconnect with new token',
      () async {
        final socketFactory = FakeSocketFactory();
        final client = FastrelayClient(
          apiKey: 'key_123',
          token: 'expired.jwt.token',
          baseUrl: 'https://api.fastrelay.io',
          httpClient: CaptureClient((_) async => jsonResponse({'ok': true})),
        );

        client.realtime = _buildRealtime(
          client,
          socketFactory,
          tokenProvider: () async => 'fresh.jwt.token',
        );
        await client.realtime!.connect();

        final socket1 = socketFactory.sockets.single;
        socket1.emitConnection(FastrelayRealtimeSocketStatus.connected);

        socket1.emitConnection(
          FastrelayRealtimeSocketStatus.disconnected,
          closeCode: 4003,
        );

        await _flush(const Duration(milliseconds: 80));

        expect(socketFactory.sockets.length, 2);
        expect(
          socketFactory.sockets.last.uri.queryParameters['token'],
          'fresh.jwt.token',
        );
        expect(client.token, 'fresh.jwt.token');

        await client.realtime!.dispose();
        client.close();
        await socketFactory.dispose();
      },
    );

    test(
      '4002 with tokenProvider refreshes once and reconnects with new token',
      () async {
        final socketFactory = FakeSocketFactory();
        final client = FastrelayClient(
          apiKey: 'key_123',
          token: 'expired.jwt.token',
          baseUrl: 'https://api.fastrelay.io',
          httpClient: CaptureClient((_) async => jsonResponse({'ok': true})),
        );

        client.realtime = _buildRealtime(
          client,
          socketFactory,
          tokenProvider: () async => 'fresh.jwt.token',
        );
        await client.realtime!.connect();

        socketFactory.sockets.single.emitConnection(
          FastrelayRealtimeSocketStatus.disconnected,
          closeCode: 4002,
        );

        await _flush(const Duration(milliseconds: 80));

        expect(socketFactory.sockets.length, 2);
        expect(
          socketFactory.sockets.last.uri.queryParameters['token'],
          'fresh.jwt.token',
        );
        expect(client.token, 'fresh.jwt.token');

        await client.realtime!.dispose();
        client.close();
        await socketFactory.dispose();
      },
    );

    test('second consecutive 4002 is fatal INVALID_TOKEN', () async {
      final socketFactory = FakeSocketFactory();
      final client = FastrelayClient(
        apiKey: 'key_123',
        token: 'expired.jwt.token',
        baseUrl: 'https://api.fastrelay.io',
        httpClient: CaptureClient((_) async => jsonResponse({'ok': true})),
      );

      client.realtime = _buildRealtime(
        client,
        socketFactory,
        tokenProvider: () async => 'still.rejected.token',
      );
      await client.realtime!.connect();

      final errors = <FastrelayRealtimeError>[];
      final errorSub = client.realtime!.errors.listen(errors.add);

      socketFactory.sockets.single.emitConnection(
        FastrelayRealtimeSocketStatus.disconnected,
        closeCode: 4002,
      );
      await _flush(const Duration(milliseconds: 80));

      socketFactory.sockets.last.emitConnection(
        FastrelayRealtimeSocketStatus.disconnected,
        closeCode: 4002,
      );
      await _flush(const Duration(milliseconds: 80));

      expect(socketFactory.sockets, hasLength(2));
      expect(errors.map((e) => e.code), contains('INVALID_TOKEN'));

      await errorSub.cancel();
      await client.realtime!.dispose();
      client.close();
      await socketFactory.dispose();
    });

    test(
      'reconnect after connection drop refreshes an expired token first',
      () async {
        final socketFactory = FakeSocketFactory();
        var now = DateTime.utc(2026, 1, 1);
        final initialToken = _jwtExpiringAt(
          now.add(const Duration(minutes: 10)),
        );
        final client = FastrelayClient(
          apiKey: 'key_123',
          token: initialToken,
          baseUrl: 'https://api.fastrelay.io',
          httpClient: CaptureClient((_) async => jsonResponse({'ok': true})),
        );

        client.realtime = FastrelayRealtime(
          client: client,
          token: initialToken,
          tokenProvider: () async => 'fresh.jwt.token',
          socketFactory: socketFactory.call,
          subscribeDebounce: const Duration(milliseconds: 8),
          reconnectInitialDelay: const Duration(milliseconds: 1),
          reconnectMaxDelay: const Duration(milliseconds: 1),
          deadConnectionTimeout: const Duration(seconds: 30),
          now: () => now,
        );
        await client.realtime!.connect();

        final socket1 = socketFactory.sockets.single;
        expect(socket1.uri.queryParameters['token'], initialToken);
        socket1.emitConnection(FastrelayRealtimeSocketStatus.connected);

        now = now.add(const Duration(hours: 1));
        socket1.emitConnection(
          FastrelayRealtimeSocketStatus.disconnected,
          closeCode: 1006,
        );

        await _flush(const Duration(milliseconds: 80));

        expect(socketFactory.sockets.length, 2);
        expect(
          socketFactory.sockets.last.uri.queryParameters['token'],
          'fresh.jwt.token',
        );
        expect(client.token, 'fresh.jwt.token');

        await client.realtime!.dispose();
        client.close();
        await socketFactory.dispose();
      },
    );

    test(
      'non-retryable disconnect surfaces errors and does not reconnect',
      () async {
        final socketFactory = FakeSocketFactory();
        final client = FastrelayClient(
          apiKey: 'key_123',
          token: 'jwt_123',
          baseUrl: 'https://api.fastrelay.io',
          httpClient: CaptureClient((_) async => jsonResponse({'ok': true})),
        );

        client.realtime = _buildRealtime(client, socketFactory);
        await client.realtime!.connect();

        final errors = <FastrelayRealtimeError>[];
        final errorSub = client.realtime!.errors.listen(errors.add);

        final socket = socketFactory.sockets.single;
        socket.emitConnection(FastrelayRealtimeSocketStatus.connected);
        socket.emitConnection(
          FastrelayRealtimeSocketStatus.disconnected,
          closeCode: 4029,
        );

        await _flush(const Duration(milliseconds: 60));

        expect(errors, isNotEmpty);
        expect(errors.first.code, 'CONNECTION_LIMIT_EXCEEDED');
        expect(socketFactory.sockets, hasLength(1));

        await errorSub.cancel();
        await client.realtime!.dispose();
        client.close();
        await socketFactory.dispose();
      },
    );

    test('lifecycle pause closes connection and resume reconnects', () async {
      final socketFactory = FakeSocketFactory();
      final client = FastrelayClient(
        apiKey: 'key_123',
        token: 'jwt_123',
        baseUrl: 'https://api.fastrelay.io',
        httpClient: CaptureClient((_) async => jsonResponse({'ok': true})),
      );

      client.realtime = _buildRealtime(client, socketFactory);
      await client.realtime!.connect();

      final socket1 = socketFactory.sockets.single;
      socket1.emitConnection(FastrelayRealtimeSocketStatus.connected);

      client.realtime!.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(socket1.isClosed, isTrue);

      client.realtime!.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await _flush(const Duration(milliseconds: 60));

      expect(socketFactory.sockets.length, 2);

      await client.realtime!.dispose();
      client.close();
      await socketFactory.dispose();
    });
  });

  group('FastrelayRealtime chat', () {
    late FakeSocketFactory socketFactory;
    late FastrelayClient client;
    late FastrelayRealtime realtime;

    setUp(() async {
      socketFactory = FakeSocketFactory();
      client = FastrelayClient(
        apiKey: 'key_123',
        token: 'jwt_123',
        baseUrl: 'https://api.fastrelay.io',
        httpClient: CaptureClient((_) async => jsonResponse({'data': []})),
      );
      realtime = _buildRealtime(client, socketFactory);
      client.realtime = realtime;
      await realtime.connect();
    });

    tearDown(() async {
      await realtime.dispose();
      client.close();
      await socketFactory.dispose();
    });

    Map<String, dynamic> messageNew({String eventId = 'evt_msg_1'}) => {
      'type': 'message.new',
      'conversationId': 'conv_1',
      'eventId': eventId,
      'createdAt': '2026-11-02T10:00:00Z',
      'data': {
        'message': {
          'id': 'msg_1',
          'conversationId': 'conv_1',
          'seq': 7,
          'type': 'regular',
          'silent': false,
          'userId': 'jane',
          'text': 'hi',
          'custom': {},
          'createdAt': '2026-11-02T10:00:00Z',
          'updatedAt': '2026-11-02T10:00:00Z',
        },
      },
    };

    test(
      'chat event without feedId reaches chatEvents, not feed listeners',
      () async {
        final socket = socketFactory.sockets.single;
        socket.emitConnection(FastrelayRealtimeSocketStatus.connected);

        final chat = <FastrelayChatEvent>[];
        final feedEvents = <FastrelayRealtimeEvent>[];
        final feedStreamEvents = <FastrelayRealtimeEvent>[];
        final chatSub = realtime.chatEvents.listen(chat.add);
        final eventsSub = realtime.events.listen(feedEvents.add);
        final feedSub = realtime
            .eventsForFeed('timeline:john')
            .listen(feedStreamEvents.add);
        await _flush();

        socket.emitJson(messageNew());
        socket.emitJson({
          'type': 'activity.created',
          'feedId': 'timeline:john',
          'eventId': 'evt_feed_1',
          'createdAt': '2026-11-02T10:00:00Z',
          'data': {'id': 'act_1'},
        });
        await _flush();

        expect(chat, hasLength(1));
        final event = chat.single;
        expect(event.type, FastrelayChatEventType.messageNew);
        expect(event.conversationId, 'conv_1');
        expect(event.eventId, 'evt_msg_1');
        expect(event.createdAt, DateTime.utc(2026, 11, 2, 10));
        expect(event.message?.id, 'msg_1');
        expect(event.message?.seq, 7);
        expect(event.message?.text, 'hi');

        expect(feedEvents.map((e) => e.eventId), ['evt_feed_1']);
        expect(feedStreamEvents.map((e) => e.eventId), ['evt_feed_1']);

        await chatSub.cancel();
        await eventsSub.cancel();
        await feedSub.cancel();
      },
    );

    test('duplicate chat eventId is dropped', () async {
      final socket = socketFactory.sockets.single;
      socket.emitConnection(FastrelayRealtimeSocketStatus.connected);

      final chat = <FastrelayChatEvent>[];
      final sub = realtime.chatEvents.listen(chat.add);

      socket.emitJson(messageNew(eventId: 'evt_dup'));
      socket.emitJson(messageNew(eventId: 'evt_dup'));
      await _flush();

      expect(chat, hasLength(1));
      await sub.cancel();
    });

    test(
      'presence.changed without conversationId and unknown types are delivered',
      () async {
        final socket = socketFactory.sockets.single;
        socket.emitConnection(FastrelayRealtimeSocketStatus.connected);

        final chat = <FastrelayChatEvent>[];
        final sub = realtime.chatEvents.listen(chat.add);

        socket.emitJson({
          'type': 'presence.changed',
          'eventId': 'evt_p1',
          'createdAt': '2026-11-02T10:00:00Z',
          'data': {
            'userId': 'jane',
            'online': false,
            'lastActiveAt': '2026-11-02T09:59:00Z',
          },
        });
        socket.emitJson({
          'type': 'reaction.future',
          'conversationId': 'conv_1',
          'eventId': 'evt_u1',
          'createdAt': '2026-11-02T10:00:00Z',
          'data': {'emoji': 'wave', 'count': 2},
        });
        await _flush();

        expect(chat, hasLength(2));
        final presence = chat.first;
        expect(presence.type, FastrelayChatEventType.presenceChanged);
        expect(presence.conversationId, isNull);
        expect(presence.userId, 'jane');
        expect(presence.online, isFalse);
        expect(presence.lastActiveAt, DateTime.utc(2026, 11, 2, 9, 59));

        final unknown = chat.last;
        expect(unknown.type, 'reaction.future');
        expect(unknown.data, {'emoji': 'wave', 'count': 2});
        expect(unknown.message, isNull);

        await sub.cancel();
      },
    );

    test('malformed typed payload does not break the socket loop', () async {
      final socket = socketFactory.sockets.single;
      socket.emitConnection(FastrelayRealtimeSocketStatus.connected);

      final chat = <FastrelayChatEvent>[];
      final sub = realtime.chatEvents.listen(chat.add);

      socket.emitJson({
        'type': 'message.new',
        'conversationId': 'conv_1',
        'eventId': 'evt_bad',
        'createdAt': '2026-11-02T10:00:00Z',
        'data': {'message': 'not-an-object'},
      });
      socket.emitJson(messageNew(eventId: 'evt_after'));
      await _flush();

      expect(chat.map((e) => e.eventId), ['evt_bad', 'evt_after']);
      expect(chat.first.message, isNull);
      expect(chat.last.message?.id, 'msg_1');

      await sub.cancel();
    });

    test('client chat messages serialize exactly', () async {
      final socket = socketFactory.sockets.single;
      socket.emitConnection(FastrelayRealtimeSocketStatus.connected);
      await _flush();
      socket.sentMessages.clear();

      expect(realtime.startTyping('conv_1'), isTrue);
      expect(realtime.stopTyping('conv_1'), isTrue);
      expect(realtime.markDelivered('conv_1', 5), isTrue);
      expect(realtime.markRead('conv_1', seq: 6), isTrue);
      expect(realtime.markRead('conv_1'), isTrue);
      realtime.startPresence();

      expect(socket.sentMessages, [
        '{"type":"typing.start","conversationId":"conv_1"}',
        '{"type":"typing.stop","conversationId":"conv_1"}',
        '{"type":"message.delivered","conversationId":"conv_1","seq":5}',
        '{"type":"conversation.read","conversationId":"conv_1","seq":6}',
        '{"type":"conversation.read","conversationId":"conv_1"}',
        '{"type":"presence.start"}',
      ]);
    });

    test('client chat messages validate input', () async {
      final socket = socketFactory.sockets.single;
      socket.emitConnection(FastrelayRealtimeSocketStatus.connected);
      await _flush();
      socket.sentMessages.clear();

      expect(() => realtime.startTyping('  '), throwsArgumentError);
      expect(() => realtime.markDelivered('conv_1', 0), throwsArgumentError);
      expect(() => realtime.markRead('conv_1', seq: -1), throwsArgumentError);
      expect(socket.sentMessages, isEmpty);
    });

    test('typing while disconnected returns false and sends nothing', () async {
      final socket = socketFactory.sockets.single;

      expect(
        realtime.connectionState,
        isNot(FastrelayConnectionState.connected),
      );
      expect(realtime.startTyping('conv_1'), isFalse);
      expect(realtime.markDelivered('conv_1', 1), isFalse);
      expect(realtime.markRead('conv_1'), isFalse);
      expect(socket.sentMessages, isEmpty);

      socket.emitConnection(FastrelayRealtimeSocketStatus.connected);
      await _flush();

      // Nothing was queued while disconnected.
      expect(
        socket.sentJsonMessages.where(
          (m) => (m['type'] as String).startsWith('typing'),
        ),
        isEmpty,
      );
    });

    test('startPresence sends now and again after a reconnect', () async {
      final socket1 = socketFactory.sockets.single;
      socket1.emitConnection(FastrelayRealtimeSocketStatus.connected);
      await _flush();

      realtime.startPresence();
      expect(
        socket1.sentJsonMessages.where((m) => m['type'] == 'presence.start'),
        hasLength(1),
      );

      socket1.emitConnection(
        FastrelayRealtimeSocketStatus.disconnected,
        closeCode: 1006,
      );
      await _flush(const Duration(milliseconds: 80));
      expect(socketFactory.sockets, hasLength(2));

      final socket2 = socketFactory.sockets.last;
      socket2.emitConnection(FastrelayRealtimeSocketStatus.connected);
      await _flush();

      expect(
        socket2.sentJsonMessages.where((m) => m['type'] == 'presence.start'),
        hasLength(1),
      );
    });

    test('startPresence while disconnected is sent once connected', () async {
      final socket = socketFactory.sockets.single;
      realtime.startPresence();
      expect(socket.sentMessages, isEmpty);

      socket.emitConnection(FastrelayRealtimeSocketStatus.connected);
      await _flush();

      expect(
        socket.sentJsonMessages.where((m) => m['type'] == 'presence.start'),
        hasLength(1),
      );
    });

    test('server error for a chat message is routed to errors', () async {
      final socket = socketFactory.sockets.single;
      socket.emitConnection(FastrelayRealtimeSocketStatus.connected);

      final errors = <FastrelayRealtimeError>[];
      final chat = <FastrelayChatEvent>[];
      final errorSub = realtime.errors.listen(errors.add);
      final chatSub = realtime.chatEvents.listen(chat.add);

      socket.emitJson({
        'type': 'error',
        'error': {
          'code': 'FORBIDDEN',
          'message': 'Not a member.',
          'hint': 'Join the conversation first.',
        },
      });
      await _flush();

      expect(errors.single.code, 'FORBIDDEN');
      expect(errors.single.hint, 'Join the conversation first.');
      expect(chat, isEmpty);

      await errorSub.cancel();
      await chatSub.cancel();
    });
  });
}
