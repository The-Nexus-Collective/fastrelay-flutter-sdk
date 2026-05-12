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
      'moderation.flags.list serializes filters and parses cursor page',
      () async {
        late http.BaseRequest captured;
        final client = FastRelayClient(
          apiKey: 'public_key',
          apiSecret: 'secret_key',
          baseUrl: 'https://api.fastrelay.dev',
          httpClient: CaptureClient((request) async {
            captured = request;
            return jsonResponse({
              'data': [
                {
                  'id': 'flag_1',
                  'reporterId': 'john',
                  'targetType': 'activity',
                  'targetId': 'act_1',
                  'reason': 'spam',
                  'status': 'pending',
                  'createdAt': '2026-03-19T10:00:00Z',
                },
              ],
              'nextCursor': 'cursor_2',
              'hasMore': true,
            });
          }),
        );

        final page = await client.moderation.flags.list(
          status: 'pending',
          targetType: 'activity',
          targetId: 'act_1',
          limit: 5,
          cursor: 'cursor_1',
        );

        expect(captured.method, 'GET');
        expect(
          captured.url.toString(),
          'https://api.fastrelay.dev/v1/moderation/flags?status=pending&targetType=activity&targetId=act_1&limit=5&cursor=cursor_1',
        );
        expect(
          captured.headers['authorization'],
          "Basic ${base64Encode(utf8.encode('public_key:secret_key'))}",
        );
        expect(page.nextCursor, 'cursor_2');
        expect(page.hasMore, isTrue);
        expect(page.data.first.targetId, 'act_1');
      },
    );

    test(
      'moderation.ban uses server auth by default and parses typed ban',
      () async {
        late http.BaseRequest captured;
        final client = FastRelayClient(
          apiKey: 'public_key',
          apiSecret: 'secret_key',
          baseUrl: 'https://api.fastrelay.dev',
          httpClient: CaptureClient((request) async {
            captured = request;
            return jsonResponse({
              'id': 'ban_1',
              'userId': 'user_bob',
              'type': 'shadow',
              'reason': 'abuse',
              'expiresAt': '2026-03-20T10:00:00Z',
              'createdAt': '2026-03-19T10:00:00Z',
            });
          }),
        );

        final ban = await client.moderation.ban(
          'user_bob',
          type: 'shadow',
          reason: 'abuse',
          expiresAt: DateTime.parse('2026-03-20T10:00:00Z'),
        );

        expect(captured.method, 'POST');
        expect(
          captured.url.toString(),
          'https://api.fastrelay.dev/v1/moderation/bans',
        );
        expect(
          captured.headers['authorization'],
          "Basic ${base64Encode(utf8.encode('public_key:secret_key'))}",
        );
        expect(jsonDecode((captured as http.Request).body), {
          'userId': 'user_bob',
          'type': 'shadow',
          'reason': 'abuse',
          'expiresAt': '2026-03-20T10:00:00.000Z',
        });
        expect(ban.userId, 'user_bob');
        expect(ban.type, 'shadow');
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

    test(
      'moderation.check uses server auth and parses typed check response',
      () async {
        late http.BaseRequest captured;
        final client = FastRelayClient(
          apiKey: 'public_key',
          apiSecret: 'secret_key',
          baseUrl: 'https://api.fastrelay.dev',
          httpClient: CaptureClient((request) async {
            captured = request;
            return jsonResponse({
              'action': 'flag',
              'matches': [
                {
                  'ruleType': 'blocklist',
                  'ruleId': 'blk_1',
                  'ruleName': 'Profanity',
                  'behavior': 'flag',
                },
              ],
            });
          }),
        );

        final result = await client.moderation.check(
          text: 'suspicious text',
          custom: {
            'details': {'lang': 'en'},
          },
        );

        expect(captured.method, 'POST');
        expect(
          captured.url.toString(),
          'https://api.fastrelay.dev/v1/moderation/check',
        );
        expect(
          captured.headers['authorization'],
          "Basic ${base64Encode(utf8.encode('public_key:secret_key'))}",
        );
        expect(jsonDecode((captured as http.Request).body), {
          'text': 'suspicious text',
          'custom': {
            'details': {'lang': 'en'},
          },
        });
        expect(result.action, 'flag');
        expect(result.matches, hasLength(1));
        expect(result.matches.first.ruleId, 'blk_1');
      },
    );
  });
}
