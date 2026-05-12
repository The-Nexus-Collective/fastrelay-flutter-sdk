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

  FastRelayRealtimeSocket call(Uri uri) {
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

class FakeSocket implements FastRelayRealtimeSocket {
  FakeSocket(this.uri);

  final Uri uri;
  final List<String> sentMessages = <String>[];

  final _messagesController = StreamController<String>.broadcast();
  final _connectionController =
      StreamController<FastRelayRealtimeSocketState>.broadcast();

  bool isClosed = false;

  @override
  Stream<FastRelayRealtimeSocketState> get connection =>
      _connectionController.stream;

  @override
  Stream<String> get messages => _messagesController.stream;

  void emitConnection(
    FastRelayRealtimeSocketStatus status, {
    int? closeCode,
    String? reason,
    Object? error,
  }) {
    if (_connectionController.isClosed) {
      return;
    }
    _connectionController.add(
      FastRelayRealtimeSocketState(
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

FastRelayRealtime _buildRealtime(
  FastRelayClient client,
  FakeSocketFactory socketFactory, {
  FastRelayTokenProvider? tokenProvider,
  bool maintainBackgroundConnection = false,
}) {
  return FastRelayRealtime(
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

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  group('FastRelayRealtime', () {
    test('connectUser enables realtime and derives websocket URL', () async {
      final fakeSocketFactory = FakeSocketFactory();

      final client = FastRelayClient(
        apiKey: 'key_123',
        baseUrl: 'https://api.fastrelay.dev',
        httpClient: CaptureClient((_) async => jsonResponse({'ok': true})),
        realtimeFactory:
            ({
              required client,
              required token,
              tokenProvider,
              maintainBackgroundConnection = false,
              FastRelayRealtimeSocketFactory? socketFactory,
            }) {
              return FastRelayRealtime(
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
        'wss://api.fastrelay.dev/v1/realtime?token=jwt_123',
      );

      await client.realtime!.dispose();
      client.close();
      await fakeSocketFactory.dispose();
    });

    test(
      'feed.events auto-subscribes, routes events, and auto-unsubscribes',
      () async {
        final socketFactory = FakeSocketFactory();
        final client = FastRelayClient(
          apiKey: 'key_123',
          token: 'jwt_123',
          baseUrl: 'https://api.fastrelay.dev',
          httpClient: CaptureClient((_) async => jsonResponse({'ok': true})),
        );

        client.realtime = _buildRealtime(client, socketFactory);
        await client.realtime!.connect();

        final socket = socketFactory.sockets.single;
        socket.emitConnection(FastRelayRealtimeSocketStatus.connected);

        final events = <FastRelayRealtimeEvent>[];
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
        final client = FastRelayClient(
          apiKey: 'key_123',
          token: 'jwt_123',
          baseUrl: 'https://api.fastrelay.dev',
          httpClient: CaptureClient((_) async => jsonResponse({'ok': true})),
        );

        client.realtime = _buildRealtime(client, socketFactory);
        await client.realtime!.connect();

        final socket = socketFactory.sockets.single;
        socket.emitConnection(FastRelayRealtimeSocketStatus.connected);

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
      final client = FastRelayClient(
        apiKey: 'key_123',
        token: 'jwt_123',
        baseUrl: 'https://api.fastrelay.dev',
        httpClient: CaptureClient((_) async => jsonResponse({'ok': true})),
      );

      client.realtime = _buildRealtime(client, socketFactory);
      await client.realtime!.connect();

      final socket = socketFactory.sockets.single;
      socket.emitConnection(FastRelayRealtimeSocketStatus.connected);

      final received = <FastRelayRealtimeEvent>[];
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
      final client = FastRelayClient(
        apiKey: 'key_123',
        token: 'jwt_123',
        baseUrl: 'https://api.fastrelay.dev',
        httpClient: CaptureClient((_) async => jsonResponse({'data': []})),
      );

      client.realtime = _buildRealtime(client, socketFactory);
      await client.realtime!.connect();

      final socket1 = socketFactory.sockets.single;
      socket1.emitConnection(FastRelayRealtimeSocketStatus.connected);

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
        FastRelayRealtimeSocketStatus.disconnected,
        closeCode: 1006,
      );

      await _flush(const Duration(milliseconds: 80));

      expect(socketFactory.sockets.length, 2);

      final socket2 = socketFactory.sockets.last;
      socket2.emitConnection(FastRelayRealtimeSocketStatus.connected);

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
      '4003 triggers tokenProvider refresh and reconnect with new token',
      () async {
        final socketFactory = FakeSocketFactory();
        final client = FastRelayClient(
          apiKey: 'key_123',
          token: 'expired.jwt.token',
          baseUrl: 'https://api.fastrelay.dev',
          httpClient: CaptureClient((_) async => jsonResponse({'ok': true})),
        );

        client.realtime = _buildRealtime(
          client,
          socketFactory,
          tokenProvider: () async => 'fresh.jwt.token',
        );
        await client.realtime!.connect();

        final socket1 = socketFactory.sockets.single;
        socket1.emitConnection(FastRelayRealtimeSocketStatus.connected);

        socket1.emitConnection(
          FastRelayRealtimeSocketStatus.disconnected,
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
      'non-retryable disconnect surfaces errors and does not reconnect',
      () async {
        final socketFactory = FakeSocketFactory();
        final client = FastRelayClient(
          apiKey: 'key_123',
          token: 'jwt_123',
          baseUrl: 'https://api.fastrelay.dev',
          httpClient: CaptureClient((_) async => jsonResponse({'ok': true})),
        );

        client.realtime = _buildRealtime(client, socketFactory);
        await client.realtime!.connect();

        final errors = <FastRelayRealtimeError>[];
        final errorSub = client.realtime!.errors.listen(errors.add);

        final socket = socketFactory.sockets.single;
        socket.emitConnection(FastRelayRealtimeSocketStatus.connected);
        socket.emitConnection(
          FastRelayRealtimeSocketStatus.disconnected,
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
      final client = FastRelayClient(
        apiKey: 'key_123',
        token: 'jwt_123',
        baseUrl: 'https://api.fastrelay.dev',
        httpClient: CaptureClient((_) async => jsonResponse({'ok': true})),
      );

      client.realtime = _buildRealtime(client, socketFactory);
      await client.realtime!.connect();

      final socket1 = socketFactory.sockets.single;
      socket1.emitConnection(FastRelayRealtimeSocketStatus.connected);

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
}
