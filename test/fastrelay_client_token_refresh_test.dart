import 'dart:convert';

import 'package:fastrelay_feed_sdk/fastrelay_feed_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _RecordingClient extends http.BaseClient {
  _RecordingClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  _handler;
  final requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    return _handler(request);
  }
}

http.StreamedResponse _json(Object? body, {int status = 200}) {
  return http.StreamedResponse(
    Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
    status,
    headers: {'content-type': 'application/json'},
  );
}

http.StreamedResponse _unauthorized() {
  return _json({
    'error': {'code': 'UNAUTHORIZED', 'message': 'Token expired'},
  }, status: 401);
}

Future<FastRelayClient> _connectedClient(
  http.Client httpClient, {
  FastRelayTokenProvider? tokenProvider,
}) async {
  final client = FastRelayClient(
    apiKey: 'key_123',
    baseUrl: 'https://api.fastrelay.io',
    httpClient: httpClient,
  );
  await client.connectUser(
    {'id': 'john'},
    'stale.jwt',
    tokenProvider: tokenProvider,
  );
  return client;
}

void main() {
  group('REST token refresh on 401', () {
    test('refreshes once and retries with the new token', () async {
      final httpClient = _RecordingClient((request) async {
        if (request.headers['authorization'] == 'Bearer stale.jwt') {
          return _unauthorized();
        }
        return _json({'id': 'act_1'});
      });
      var providerCalls = 0;
      final client = await _connectedClient(
        httpClient,
        tokenProvider: () async {
          providerCalls++;
          return 'fresh.jwt';
        },
      );

      final activity = await client.getActivity('act_1');

      expect(activity['id'], 'act_1');
      expect(providerCalls, 1);
      expect(httpClient.requests, hasLength(2));
      expect(
        httpClient.requests.last.headers['authorization'],
        'Bearer fresh.jwt',
      );
      expect(client.token, 'fresh.jwt');
    });

    test('second 401 after refresh propagates, no retry loop', () async {
      final httpClient = _RecordingClient((_) async => _unauthorized());
      var providerCalls = 0;
      final client = await _connectedClient(
        httpClient,
        tokenProvider: () async {
          providerCalls++;
          return 'fresh.jwt';
        },
      );

      await expectLater(
        client.getActivity('act_1'),
        throwsA(
          isA<FastRelayApiError>().having((e) => e.status, 'status', 401),
        ),
      );
      expect(providerCalls, 1);
      expect(httpClient.requests, hasLength(2));
    });

    test('401 without tokenProvider propagates without retry', () async {
      final httpClient = _RecordingClient((_) async => _unauthorized());
      final client = await _connectedClient(httpClient);

      await expectLater(
        client.getActivity('act_1'),
        throwsA(
          isA<FastRelayApiError>().having((e) => e.status, 'status', 401),
        ),
      );
      expect(httpClient.requests, hasLength(1));
    });

    test('concurrent 401s share one provider call', () async {
      final httpClient = _RecordingClient((request) async {
        if (request.headers['authorization'] == 'Bearer stale.jwt') {
          return _unauthorized();
        }
        return _json({'id': request.url.pathSegments.last});
      });
      var providerCalls = 0;
      final client = await _connectedClient(
        httpClient,
        tokenProvider: () async {
          providerCalls++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return 'fresh.jwt';
        },
      );

      final results = await Future.wait([
        client.getActivity('act_1'),
        client.getActivity('act_2'),
      ]);

      expect(results.map((a) => a['id']), ['act_1', 'act_2']);
      expect(providerCalls, 1);
    });
  });
}
