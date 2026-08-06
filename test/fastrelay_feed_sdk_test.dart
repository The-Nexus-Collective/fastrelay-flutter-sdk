import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fastrelay_feed_sdk/fastrelay_feed_sdk.dart';

http.Response jsonResponse(
  Object? body, {
  int status = 200,
  Map<String, String> headers = const {},
}) {
  return http.Response(
    body == null ? '' : jsonEncode(body),
    status,
    headers: {'content-type': 'application/json', ...headers},
  );
}

void main() {
  test(
    'feed.addActivity injects feed id and sends camelCase payload',
    () async {
      late http.Request captured;
      final fastrelay = FastRelayClient(
        apiKey: 'key_123',
        token: 'jwt_123',
        baseUrl: 'https://api.fastrelay.dev',
        httpClient: MockClient((request) async {
          captured = request;
          return jsonResponse({
            'id': 'act_1',
            'type': 'post',
            'userId': 'john',
            'feeds': ['timeline:john'],
          });
        }),
      );

      final activity = await fastrelay.feed('timeline', 'john').addActivity({
        'type': 'post',
        'text': 'hello',
      });

      expect(captured.method, 'POST');
      expect(captured.headers['authorization'], 'Bearer jwt_123');
      expect(
        captured.url.toString(),
        'https://api.fastrelay.dev/v1/activities',
      );
      expect(jsonDecode(captured.body), {
        'type': 'post',
        'text': 'hello',
        'feeds': ['timeline:john'],
      });

      expect((activity as Map<String, dynamic>)['userId'], 'john');
    },
  );

  test('feed.getActivities serializes filter params and markRead', () async {
    late http.Request captured;
    final fastrelay = FastRelayClient(
      apiKey: 'key_123',
      token: 'jwt_123',
      baseUrl: 'https://api.fastrelay.dev',
      httpClient: MockClient((request) async {
        captured = request;
        return jsonResponse({
          'data': [
            {'id': 'act_1', 'type': 'post'},
          ],
          'nextCursor': 'cursor_2',
          'hasMore': true,
        });
      }),
    );

    final page = await fastrelay
        .feed('timeline', 'john')
        .getActivities(
          query: {
            'limit': 10,
            'cursor': 'cursor_1',
            'markSeen': true,
            'markRead': ['act_1', 'act_2'],
            'filter': {'type': 'post', 'custom.category': 'tech'},
          },
        );

    expect(captured.url.queryParameters['limit'], '10');
    expect(captured.url.queryParameters['cursor'], 'cursor_1');
    expect(captured.url.queryParameters['markSeen'], 'true');
    expect(captured.url.queryParameters['markRead'], 'act_1,act_2');
    expect(captured.url.queryParameters['filter[type]'], 'post');
    expect(captured.url.queryParameters['filter[custom.category]'], 'tech');

    expect((page as Map<String, dynamic>)['nextCursor'], 'cursor_2');
    expect(page['hasMore'], isTrue);
  });

  test('requests without a token are sent unauthenticated', () async {
    late http.Request captured;
    final fastrelay = FastRelayClient(
      apiKey: 'public_key',
      baseUrl: 'https://api.fastrelay.dev',
      httpClient: MockClient((request) async {
        captured = request;
        return jsonResponse({'id': 'john'});
      }),
    );

    await fastrelay.getUser('john');

    expect(captured.headers.containsKey('authorization'), isFalse);
  });

  test('capabilities namespace fetches capability payload', () async {
    late http.Request captured;
    final fastrelay = FastRelayClient(
      apiKey: 'key_123',
      token: 'jwt_123',
      baseUrl: 'https://api.fastrelay.dev',
      httpClient: MockClient((request) async {
        captured = request;
        return jsonResponse({
          'canAddActivity': true,
          'canDeleteOwnActivity': true,
        });
      }),
    );

    final response = await fastrelay.capabilities.get({
      'feed': 'timeline:john',
    });

    expect(captured.method, 'GET');
    expect(
      captured.url.toString(),
      'https://api.fastrelay.dev/v1/me/capabilities?feed=timeline%3Ajohn',
    );
    expect(response['canAddActivity'], isTrue);
    expect(response['canDeleteOwnActivity'], isTrue);
  });

  test('feed.getCapabilities scopes to feed id by default', () async {
    late http.Request captured;
    final fastrelay = FastRelayClient(
      apiKey: 'key_123',
      token: 'jwt_123',
      baseUrl: 'https://api.fastrelay.dev',
      httpClient: MockClient((request) async {
        captured = request;
        return jsonResponse({'canAddActivity': true});
      }),
    );

    final response = await fastrelay.feed('timeline', 'john').getCapabilities();

    expect(captured.method, 'GET');
    expect(
      captured.url.toString(),
      'https://api.fastrelay.dev/v1/me/capabilities?feed=timeline%3Ajohn',
    );
    expect((response as Map<String, dynamic>)['canAddActivity'], isTrue);
  });

  test('maps API errors to FastRelayApiError', () async {
    final fastrelay = FastRelayClient(
      apiKey: 'key_123',
      token: 'jwt_123',
      httpClient: MockClient((_) async {
        return jsonResponse({
          'error': {
            'code': 'ACTIVITY_NOT_FOUND',
            'message': "Activity with ID 'act_missing' was not found.",
            'details': {'activityId': 'act_missing'},
            'hint': 'Verify the activity ID is correct.',
            'docUrl': 'https://docs.fastrelay.dev/errors/ACTIVITY_NOT_FOUND',
          },
          'requestId': 'req_123',
        }, status: 404);
      }),
    );

    await expectLater(
      () => fastrelay.activities.get('act_missing'),
      throwsA(
        isA<FastRelayApiError>()
            .having((error) => error.status, 'status', 404)
            .having((error) => error.code, 'code', 'ACTIVITY_NOT_FOUND')
            .having((error) => error.requestId, 'requestId', 'req_123')
            .having(
              (error) => (error.details as Map)['activityId'],
              'details.activityId',
              'act_missing',
            )
            .having(
              (error) => error.docUrl,
              'docUrl',
              'https://docs.fastrelay.dev/errors/ACTIVITY_NOT_FOUND',
            ),
      ),
    );
  });

  test('connectUser with upsertUser self-upserts via POST /v1/users', () async {
    final requests = <http.Request>[];
    final fastrelay = FastRelayClient(
      apiKey: 'key_123',
      baseUrl: 'https://api.fastrelay.dev',
      httpClient: MockClient((request) async {
        requests.add(request);
        return jsonResponse({'id': 'john'});
      }),
    );

    await fastrelay.connectUser(
      {
        'id': 'john',
        'displayName': 'John',
        'profileData': {'language': 'en'},
      },
      'jwt_123',
      upsertUser: true,
    );

    expect(requests, hasLength(1));
    final captured = requests.single;
    expect(captured.method, 'POST');
    expect(captured.url.toString(), 'https://api.fastrelay.dev/v1/users');
    expect(captured.headers['authorization'], 'Bearer jwt_123');
    expect(jsonDecode(captured.body), {
      'id': 'john',
      'displayName': 'John',
      'profileData': {'language': 'en'},
    });
  });

  test('connectUser without upsertUser makes no requests', () async {
    final requests = <http.Request>[];
    final fastrelay = FastRelayClient(
      apiKey: 'key_123',
      httpClient: MockClient((request) async {
        requests.add(request);
        return jsonResponse({});
      }),
    );

    await fastrelay.connectUser({'id': 'john'}, 'jwt_123');

    expect(requests, isEmpty);
  });
}
