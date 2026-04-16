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
    'feed.addActivity injects feed id and sends snake_case payload',
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
            'user_id': 'john',
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

  test('feed.getActivities serializes filter params and mark_read', () async {
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
          'next_cursor': 'cursor_2',
          'has_more': true,
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
    expect(captured.url.queryParameters['mark_seen'], 'true');
    expect(captured.url.queryParameters['mark_read'], 'act_1,act_2');
    expect(captured.url.queryParameters['filter[type]'], 'post');
    expect(captured.url.queryParameters['filter[custom.category]'], 'tech');

    expect((page as Map<String, dynamic>)['nextCursor'], 'cursor_2');
    expect(page['hasMore'], isTrue);
  });

  test('issueToken uses Basic auth and maps request to snake_case', () async {
    late http.Request captured;
    final fastrelay = FastRelayClient(
      apiKey: 'public_key',
      apiSecret: 'secret_key',
      baseUrl: 'https://api.fastrelay.dev',
      httpClient: MockClient((request) async {
        captured = request;
        return jsonResponse({'token': 'jwt_issued'});
      }),
    );

    final response = await fastrelay.issueToken({
      'userId': 'john',
      'role': 'user',
      'expiresIn': 3600,
    });

    expect(response['token'], 'jwt_issued');
    expect(captured.url.toString(), 'https://api.fastrelay.dev/v1/tokens');
    expect(captured.method, 'POST');
    expect(
      captured.headers['authorization'],
      'Basic ${base64Encode(utf8.encode('public_key:secret_key'))}',
    );

    expect(jsonDecode(captured.body), {
      'user_id': 'john',
      'role': 'user',
      'expires_in': 3600,
    });
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
          'can_add_activity': true,
          'can_delete_own_activity': true,
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
        return jsonResponse({'can_add_activity': true});
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
            'details': {'activity_id': 'act_missing'},
            'hint': 'Verify the activity ID is correct.',
            'doc_url': 'https://docs.fastrelay.dev/errors/ACTIVITY_NOT_FOUND',
          },
          'request_id': 'req_123',
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
}
