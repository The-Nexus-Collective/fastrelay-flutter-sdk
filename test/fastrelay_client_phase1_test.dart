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
  group('phase 1 client methods', () {
    test(
      'addReaction posts reaction payload and parses typed response',
      () async {
        late http.BaseRequest captured;
        final client = FastRelayClient(
          apiKey: 'key_123',
          token: 'jwt_123',
          baseUrl: 'https://api.fastrelay.io',
          httpClient: CaptureClient((request) async {
            captured = request;
            return jsonResponse({
              'id': 'reaction_1',
              'activityId': 'act_1',
              'userId': 'john',
              'type': 'like',
              'createdAt': '2026-02-25T10:00:00Z',
            });
          }),
        );

        final reaction = await client.addReaction('act_1', type: 'like');

        expect(captured.method, 'POST');
        expect(
          captured.url.toString(),
          'https://api.fastrelay.io/v1/activities/act_1/reactions',
        );
        expect(
          (captured as http.Request).headers['authorization'],
          'Bearer jwt_123',
        );
        expect(jsonDecode((captured as http.Request).body), {'type': 'like'});
        expect(reaction.id, 'reaction_1');
        expect(reaction.activityId, 'act_1');
        expect(reaction.userId, 'john');
      },
    );

    test('listReactions serializes filters and parses cursor page', () async {
      late http.BaseRequest captured;
      final client = FastRelayClient(
        apiKey: 'key_123',
        token: 'jwt_123',
        baseUrl: 'https://api.fastrelay.io',
        httpClient: CaptureClient((request) async {
          captured = request;
          return jsonResponse({
            'data': [
              {
                'id': 'reaction_1',
                'activityId': 'act_1',
                'userId': 'john',
                'type': 'wow',
                'createdAt': '2026-02-25T10:00:00Z',
              },
            ],
            'nextCursor': 'cursor_2',
            'hasMore': true,
          });
        }),
      );

      final page = await client.listReactions(
        'act_1',
        type: 'wow',
        limit: 5,
        cursor: 'cursor_1',
      );

      expect(captured.url.queryParameters['type'], 'wow');
      expect(captured.url.queryParameters['limit'], '5');
      expect(captured.url.queryParameters['cursor'], 'cursor_1');
      expect(page.data, hasLength(1));
      expect(page.nextCursor, 'cursor_2');
      expect(page.hasMore, isTrue);
    });

    test(
      'comment methods serialize camelCase and return typed comments',
      () async {
        late http.BaseRequest addRequest;
        late http.BaseRequest listRequest;
        var requestCount = 0;

        final client = FastRelayClient(
          apiKey: 'key_123',
          token: 'jwt_123',
          baseUrl: 'https://api.fastrelay.io',
          httpClient: CaptureClient((request) async {
            requestCount += 1;
            if (requestCount == 1) {
              addRequest = request;
              return jsonResponse({
                'id': 'comment_1',
                'activityId': 'act_1',
                'userId': 'john',
                'text': 'hello',
                'parentId': null,
                'mentionedUsers': ['jane'],
                'reactionCounts': {'like': 1},
                'score': 1.25,
                'createdAt': '2026-02-25T10:00:00Z',
                'updatedAt': '2026-02-25T10:00:00Z',
              });
            }

            listRequest = request;
            return jsonResponse({
              'data': [
                {
                  'id': 'comment_1',
                  'activityId': 'act_1',
                  'userId': 'john',
                  'text': 'hello',
                  'parentId': null,
                  'mentionedUsers': ['jane'],
                  'reactionCounts': {'like': 1},
                  'score': 1.25,
                  'createdAt': '2026-02-25T10:00:00Z',
                  'updatedAt': '2026-02-25T10:00:00Z',
                },
              ],
              'nextCursor': null,
              'hasMore': false,
            });
          }),
        );

        final created = await client.addComment(
          'act_1',
          text: 'hello',
          mentionedUsers: const ['jane'],
        );
        final page = await client.listComments(
          'act_1',
          sort: 'newest',
          limit: 10,
        );

        expect(jsonDecode((addRequest as http.Request).body), {
          'text': 'hello',
          'mentionedUsers': ['jane'],
        });
        expect(listRequest.url.queryParameters['sort'], 'newest');
        expect(listRequest.url.queryParameters['limit'], '10');
        expect(created.id, 'comment_1');
        expect(created.mentionedUsers, ['jane']);
        expect(page.data.first.id, 'comment_1');
      },
    );

    test('comment reaction methods send expected paths', () async {
      final paths = <String>[];
      final client = FastRelayClient(
        apiKey: 'key_123',
        token: 'jwt_123',
        baseUrl: 'https://api.fastrelay.io',
        httpClient: CaptureClient((request) async {
          paths.add(request.url.path);
          if (request.method == 'POST') {
            return jsonResponse({
              'id': 'cr_1',
              'commentId': 'comment_1',
              'userId': 'john',
              'type': 'like',
              'createdAt': '2026-02-25T10:00:00Z',
            });
          }
          return jsonResponse(null, status: 204);
        }),
      );

      final reaction = await client.addCommentReaction(
        'comment_1',
        type: 'like',
      );
      await client.removeCommentReaction('comment_1', 'cr_1');

      expect(paths.first, '/v1/comments/comment_1/reactions');
      expect(paths.last, '/v1/comments/comment_1/reactions/cr_1');
      expect(reaction.commentId, 'comment_1');
      expect(reaction.type, 'like');
    });

    test('bookmark methods parse typed responses', () async {
      var requestCount = 0;
      final client = FastRelayClient(
        apiKey: 'key_123',
        token: 'jwt_123',
        baseUrl: 'https://api.fastrelay.io',
        httpClient: CaptureClient((request) async {
          requestCount += 1;
          if (requestCount == 1) {
            return jsonResponse({
              'id': 'bookmark_1',
              'activityId': 'act_1',
              'userId': 'john',
              'createdAt': '2026-02-25T10:00:00Z',
            });
          }
          return jsonResponse({
            'data': [
              {
                'id': 'bookmark_1',
                'activityId': 'act_1',
                'userId': 'john',
                'createdAt': '2026-02-25T10:00:00Z',
              },
            ],
            'nextCursor': null,
            'hasMore': false,
          });
        }),
      );

      final bookmark = await client.addBookmark('act_1');
      final page = await client.listBookmarks(limit: 25);

      expect(bookmark.activityId, 'act_1');
      expect(page.data.first.id, 'bookmark_1');
    });

    test('poll methods map choices/options and optionId payload', () async {
      final requests = <http.BaseRequest>[];
      final client = FastRelayClient(
        apiKey: 'key_123',
        token: 'jwt_123',
        baseUrl: 'https://api.fastrelay.io',
        httpClient: CaptureClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/votes')) {
            return jsonResponse({
              'id': 'poll_1',
              'question': 'Best SDK?',
              'options': [
                {'id': 'opt_1', 'text': 'FastRelay', 'voteCount': 1},
              ],
              'totalVotes': 1,
              'userVote': {'optionId': 'opt_1'},
              'isClosed': false,
            });
          }

          return jsonResponse({
            'id': 'poll_1',
            'question': 'Best SDK?',
            'options': [
              {'id': 'opt_1', 'text': 'FastRelay', 'voteCount': 0},
            ],
            'totalVotes': 0,
            'userVote': null,
            'isClosed': false,
          });
        }),
      );

      final poll = await client.createPoll(
        'act_1',
        question: 'Best SDK?',
        choices: const [
          {'id': 'opt_1', 'text': 'FastRelay'},
        ],
        maxVotesPerUser: 2,
        anonymous: true,
      );
      final votedPoll = await client.vote('poll_1', optionId: 'opt_1');

      final createBody = jsonDecode((requests.first as http.Request).body);
      final voteBody = jsonDecode((requests.last as http.Request).body);

      expect(createBody['options'], [
        {'id': 'opt_1', 'text': 'FastRelay'},
      ]);
      expect(createBody['maxVotesPerUser'], 2);
      expect(createBody['anonymous'], isTrue);
      expect(voteBody, {'optionId': 'opt_1'});
      expect(poll.id, 'poll_1');
      expect(votedPoll.userVote, 'opt_1');
      expect(votedPoll.hasVoted, isTrue);
    });

    test('uploadFile sends multipart request and parses response', () async {
      late http.BaseRequest captured;
      final client = FastRelayClient(
        apiKey: 'key_123',
        token: 'jwt_123',
        baseUrl: 'https://api.fastrelay.io',
        httpClient: CaptureClient((request) async {
          captured = request;
          return jsonResponse({
            'id': 'file_1',
            'url': 'https://cdn.fastrelay.io/file_1.png',
            'type': 'image',
            'mimeType': 'image/png',
            'size': 4,
            'metadata': {},
            'createdAt': '2026-02-25T10:00:00Z',
          });
        }),
      );

      final file = await client.uploadFile(
        const [0, 1, 2, 3],
        'avatar.png',
        type: 'image',
      );

      expect(captured, isA<http.MultipartRequest>());
      final multipart = captured as http.MultipartRequest;
      expect(multipart.method, 'POST');
      expect(multipart.url.toString(), 'https://api.fastrelay.io/v1/files');
      expect(multipart.fields['type'], 'image');
      expect(multipart.files, hasLength(1));
      expect(multipart.files.first.filename, 'avatar.png');
      expect(file.id, 'file_1');
      expect(file.mimeType, 'image/png');
      expect(file.size, 4);
    });

    test('uploadFileDirect reserves, PUTs to storage and confirms', () async {
      final requests = <http.BaseRequest>[];
      final client = FastRelayClient(
        apiKey: 'key_123',
        token: 'jwt_123',
        baseUrl: 'https://api.fastrelay.io',
        httpClient: CaptureClient((request) async {
          requests.add(request);
          switch (requests.length) {
            case 1:
              return jsonResponse({
                'fileId': 'file_1',
                'uploadUrl':
                    'https://bucket.spaces.test/feed/file_1.png?X-Amz-Signature=sig',
                'requiredHeaders': {
                  'content-type': 'image/png',
                  'content-length': '4',
                },
                'expiresAt': '2026-10-30T10:15:00Z',
              });
            case 2:
              return http.StreamedResponse(const Stream.empty(), 200);
            default:
              return jsonResponse({
                'id': 'file_1',
                'url': 'https://cdn.fastrelay.io/file_1.png',
                'type': 'image',
                'mimeType': 'image/png',
                'size': 4,
                'metadata': {},
                'createdAt': '2026-10-30T10:00:00Z',
              });
          }
        }),
      );

      final file = await client.uploadFileDirect(const [
        0,
        1,
        2,
        3,
      ], 'image/png');

      expect(requests, hasLength(3));
      final create = requests[0] as http.Request;
      expect(
        create.url.toString(),
        'https://api.fastrelay.io/v1/files/uploads',
      );
      expect(jsonDecode(create.body), {
        'contentType': 'image/png',
        'sizeBytes': 4,
      });

      final put = requests[1] as http.Request;
      expect(put.method, 'PUT');
      expect(put.url.host, 'bucket.spaces.test');
      expect(put.headers['content-type'], 'image/png');
      expect(put.headers.containsKey('authorization'), isFalse);
      expect(put.headers.containsKey('content-length'), isFalse);
      expect(put.bodyBytes, [0, 1, 2, 3]);

      final confirm = requests[2];
      expect(confirm.method, 'POST');
      expect(
        confirm.url.toString(),
        'https://api.fastrelay.io/v1/files/file_1/confirm',
      );
      expect(file.id, 'file_1');
      expect(file.url, 'https://cdn.fastrelay.io/file_1.png');
    });

    test('uploadFileDirect does not confirm when the PUT fails', () async {
      final requests = <http.BaseRequest>[];
      final client = FastRelayClient(
        apiKey: 'key_123',
        token: 'jwt_123',
        baseUrl: 'https://api.fastrelay.io',
        httpClient: CaptureClient((request) async {
          requests.add(request);
          if (requests.length == 1) {
            return jsonResponse({
              'fileId': 'file_1',
              'uploadUrl': 'https://bucket.spaces.test/feed/file_1.png',
              'requiredHeaders': {'content-type': 'image/png'},
              'expiresAt': '2026-10-30T10:15:00Z',
            });
          }
          return http.StreamedResponse(
            Stream.value(utf8.encode('<Error>SignatureDoesNotMatch</Error>')),
            403,
          );
        }),
      );

      await expectLater(
        client.uploadFileDirect(const [0, 1, 2, 3], 'image/png'),
        throwsA(
          isA<FastRelayApiError>()
              .having((e) => e.status, 'status', 403)
              .having((e) => e.method, 'method', 'PUT'),
        ),
      );
      expect(requests, hasLength(2));
    });

    test('submitFeedback validates type and posts payload', () async {
      late http.BaseRequest captured;
      final client = FastRelayClient(
        apiKey: 'key_123',
        token: 'jwt_123',
        baseUrl: 'https://api.fastrelay.io',
        httpClient: CaptureClient((request) async {
          captured = request;
          return jsonResponse({
            'id': 'feedback_1',
            'activityId': 'act_1',
            'userId': 'john',
            'type': 'show_more',
            'createdAt': '2026-02-25T10:00:00Z',
          });
        }),
      );

      await expectLater(
        () => client.submitFeedback('act_1', type: 'invalid'),
        throwsArgumentError,
      );

      final feedback = await client.submitFeedback('act_1', type: 'show_more');

      expect(jsonDecode((captured as http.Request).body), {
        'type': 'show_more',
      });
      expect(feedback.isShowMore, isTrue);
    });

    test('typed feed methods parse cursor and notification pages', () async {
      var requestCount = 0;
      final client = FastRelayClient(
        apiKey: 'key_123',
        token: 'jwt_123',
        baseUrl: 'https://api.fastrelay.io',
        httpClient: CaptureClient((_) async {
          requestCount += 1;
          return jsonResponse({
            'data': [
              {
                'id': 'act_$requestCount',
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
            'nextCursor': 'next_1',
            'hasMore': true,
            'unseenCount': 4,
            'unreadCount': 2,
          });
        }),
      );

      final feed = client.feed('timeline', 'john');
      final activityPage = await feed.getActivityList();
      final notificationPage = await feed.getNotificationActivities();

      expect(activityPage.data.first.id, 'act_1');
      expect(activityPage.nextCursor, 'next_1');
      expect(notificationPage.unseenCount, 4);
      expect(notificationPage.unreadCount, 2);
    });

    test('namespaced APIs delegate to typed methods', () async {
      final client = FastRelayClient(
        apiKey: 'key_123',
        token: 'jwt_123',
        baseUrl: 'https://api.fastrelay.io',
        httpClient: CaptureClient((request) async {
          if (request.url.path.endsWith('/reactions')) {
            return jsonResponse({
              'id': 'reaction_1',
              'activityId': 'act_1',
              'userId': 'john',
              'type': 'like',
              'createdAt': '2026-02-25T10:00:00Z',
            });
          }
          return jsonResponse(null, status: 204);
        }),
      );

      final reaction = await client.reactions.add('act_1', type: 'like');
      await client.reactions.remove('act_1', 'reaction_1');

      expect(reaction.type, 'like');
      expect(reaction.activityId, 'act_1');
    });
  });
}
