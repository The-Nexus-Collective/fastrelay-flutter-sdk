import 'dart:async';
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

Map<String, dynamic> feedResponse(String id, {int unseen = 0, int unread = 0}) {
  return {
    'data': [
      {
        'id': id,
        'type': 'post',
        'text': 'hello',
        'userId': 'john',
        'feeds': ['timeline:john'],
        'visibility': 'public',
        'custom': {},
        'popularity': 0,
        'reactionCounts': {'like': 1},
        'commentCount': 0,
        'bookmarkCount': 0,
        'createdAt': '2026-02-25T10:00:00Z',
        'updatedAt': '2026-02-25T10:00:00Z',
      },
    ],
    'nextCursor': null,
    'hasMore': false,
    'unseenCount': unseen,
    'unreadCount': unread,
  };
}

void main() {
  group('FeedPollingService', () {
    test('pollFeed emits initial and interval updates', () async {
      var count = 0;
      final client = FastRelayClient(
        apiKey: 'key_123',
        token: 'jwt_123',
        baseUrl: 'https://api.fastrelay.dev',
        httpClient: CaptureClient((_) async {
          count += 1;
          return jsonResponse(feedResponse('act_$count'));
        }),
      );

      final service = FeedPollingService(
        client: client,
        activeInterval: const Duration(milliseconds: 30),
        backgroundInterval: const Duration(milliseconds: 150),
      );

      final stream = service.pollFeed('timeline', 'john', limit: 1);
      final first = await stream.first.timeout(const Duration(seconds: 1));

      expect(first.data.first.id, 'act_1');

      await Future<void>.delayed(const Duration(milliseconds: 90));
      expect(count, greaterThanOrEqualTo(3));

      service.dispose();
      client.close();
    });

    test('pause and resume adjust polling behavior', () async {
      var count = 0;
      final client = FastRelayClient(
        apiKey: 'key_123',
        token: 'jwt_123',
        baseUrl: 'https://api.fastrelay.dev',
        httpClient: CaptureClient((_) async {
          count += 1;
          return jsonResponse(feedResponse('act_$count'));
        }),
      );

      final service = FeedPollingService(
        client: client,
        activeInterval: const Duration(milliseconds: 20),
        backgroundInterval: const Duration(milliseconds: 250),
      );

      final subscription = service.pollFeed('timeline', 'john').listen((_) {});

      await Future<void>.delayed(const Duration(milliseconds: 75));
      final beforePause = count;

      service.pause();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final duringPause = count;

      service.resume();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final afterResume = count;

      expect(beforePause, greaterThanOrEqualTo(2));
      expect(duringPause - beforePause, lessThanOrEqualTo(1));
      expect(afterResume, greaterThan(duringPause));

      await subscription.cancel();
      service.dispose();
      client.close();
    });

    test('polling errors are emitted and stream continues', () async {
      var count = 0;
      final client = FastRelayClient(
        apiKey: 'key_123',
        token: 'jwt_123',
        baseUrl: 'https://api.fastrelay.dev',
        httpClient: CaptureClient((_) async {
          count += 1;
          if (count == 1) {
            return jsonResponse({
              'error': {'code': 'TEMP_ERROR', 'message': 'Temporary failure'},
            }, status: 500);
          }
          return jsonResponse(feedResponse('act_$count'));
        }),
      );

      final service = FeedPollingService(
        client: client,
        activeInterval: const Duration(milliseconds: 30),
        backgroundInterval: const Duration(milliseconds: 150),
      );

      final errorCompleter = Completer<void>();
      final dataCompleter = Completer<CursorPage<FastRelayActivity>>();

      final subscription = service
          .pollFeed('timeline', 'john')
          .listen(
            (page) {
              if (!dataCompleter.isCompleted) {
                dataCompleter.complete(page);
              }
            },
            onError: (_) {
              if (!errorCompleter.isCompleted) {
                errorCompleter.complete();
              }
            },
          );

      await errorCompleter.future.timeout(const Duration(seconds: 1));
      final page = await dataCompleter.future.timeout(
        const Duration(seconds: 1),
      );

      expect(page.data.first.id, startsWith('act_'));
      expect(count, greaterThanOrEqualTo(2));

      await subscription.cancel();
      service.dispose();
      client.close();
    });

    test('pollNotifications emits notification counters', () async {
      final client = FastRelayClient(
        apiKey: 'key_123',
        token: 'jwt_123',
        baseUrl: 'https://api.fastrelay.dev',
        httpClient: CaptureClient((_) async {
          return jsonResponse(feedResponse('act_1', unseen: 5, unread: 2));
        }),
      );

      final service = FeedPollingService(
        client: client,
        activeInterval: const Duration(milliseconds: 30),
      );

      final page = await service
          .pollNotifications('notification', 'john')
          .first
          .timeout(const Duration(seconds: 1));

      expect(page.data.first.id, 'act_1');
      expect(page.unseenCount, 5);
      expect(page.unreadCount, 2);

      service.dispose();
      client.close();
    });
  });
}
