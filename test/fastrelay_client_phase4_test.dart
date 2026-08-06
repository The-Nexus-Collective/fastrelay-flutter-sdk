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

void main() {
  group('phase 4 moderation client methods', () {
    test(
      'moderation.flag posts camelCase payload and parses typed flag',
      () async {
        late http.BaseRequest captured;
        final client = FastRelayClient(
          apiKey: 'key_123',
          token: 'jwt_123',
          baseUrl: 'https://api.fastrelay.dev',
          httpClient: CaptureClient((request) async {
            captured = request;
            return jsonResponse({
              'id': 'flag_1',
              'reporterId': 'john',
              'targetType': 'activity',
              'targetId': 'act_1',
              'reason': 'spam',
              'description': 'Looks bad',
              'status': 'pending',
              'createdAt': '2026-03-19T10:00:00Z',
            });
          }),
        );

        final flag = await client.moderation.flag(
          'activity',
          'act_1',
          reason: 'spam',
          description: 'Looks bad',
        );

        expect(captured.method, 'POST');
        expect(
          captured.url.toString(),
          'https://api.fastrelay.dev/v1/moderation/flags',
        );
        expect(
          (captured as http.Request).headers['authorization'],
          'Bearer jwt_123',
        );
        expect(jsonDecode((captured as http.Request).body), {
          'targetType': 'activity',
          'targetId': 'act_1',
          'reason': 'spam',
          'description': 'Looks bad',
        });
        expect(flag.targetType, 'activity');
        expect(flag.reporterId, 'john');
        expect(flag.status, 'pending');
      },
    );

    test(
      'moderation.getMutedUsers serializes query and parses typed mutes',
      () async {
        late http.BaseRequest captured;
        final client = FastRelayClient(
          apiKey: 'key_123',
          token: 'jwt_123',
          baseUrl: 'https://api.fastrelay.dev',
          httpClient: CaptureClient((request) async {
            captured = request;
            return jsonResponse({
              'data': [
                {
                  'id': 'mut_1',
                  'mutedUserId': 'user_bob',
                  'type': 'personal',
                  'createdAt': '2026-03-19T10:00:00Z',
                },
              ],
              'nextCursor': null,
              'hasMore': false,
            });
          }),
        );

        final page = await client.moderation.getMutedUsers(
          type: 'personal',
          limit: 10,
          cursor: 'cursor_1',
        );

        expect(captured.method, 'GET');
        expect(
          captured.url.toString(),
          'https://api.fastrelay.dev/v1/moderation/mutes?type=personal&limit=10&cursor=cursor_1',
        );
        expect(captured.headers['authorization'], 'Bearer jwt_123');
        expect(page.hasMore, isFalse);
        expect(page.data.first.mutedUserId, 'user_bob');
      },
    );

    test('server auth mode is rejected in the client-only SDK', () async {
      final client = FastRelayClient(
        apiKey: 'public_key',
        baseUrl: 'https://api.fastrelay.dev',
        httpClient: CaptureClient((request) async => jsonResponse({})),
      );

      expect(
        () => client.getUser(
          'john',
          options: const FastRelayRequestOptions(
            auth: FastRelayAuthMode.server,
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('client-only'),
          ),
        ),
      );
    });
  });
}
