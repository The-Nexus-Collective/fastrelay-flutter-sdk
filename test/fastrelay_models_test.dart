import 'package:fastrelay_feed_sdk/fastrelay_feed_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('models', () {
    test('CursorPage parses generic data', () {
      final page = CursorPage<FastRelayReaction>.fromJson({
        'data': [
          {
            'id': 'r1',
            'activityId': 'a1',
            'userId': 'u1',
            'type': 'like',
            'createdAt': '2026-02-25T10:00:00Z',
          },
        ],
        'nextCursor': 'next_1',
        'hasMore': true,
      }, FastRelayReaction.fromJson);

      expect(page.data, hasLength(1));
      expect(page.data.first.id, 'r1');
      expect(page.nextCursor, 'next_1');
      expect(page.hasMore, isTrue);
    });

    test('NotificationPage parses unseen and unread counters', () {
      final page = NotificationPage<FastRelayActivity>.fromJson({
        'data': [
          {
            'id': 'act_1',
            'type': 'post',
            'userId': 'john',
            'feeds': ['timeline:john'],
            'createdAt': '2026-02-25T10:00:00Z',
            'updatedAt': '2026-02-25T10:00:00Z',
          },
        ],
        'nextCursor': null,
        'hasMore': false,
        'unseenCount': 3,
        'unreadCount': 2,
      }, FastRelayActivity.fromJson);

      expect(page.unseenCount, 3);
      expect(page.unreadCount, 2);
      expect(page.data.first.id, 'act_1');
      expect(page.groups, isEmpty);
      expect(page.isAggregated, isFalse);
    });

    test('NotificationPage parses aggregated groups payload', () {
      final page = NotificationPage<FastRelayActivity>.fromJson({
        'groups': [
          {
            'groupKey': 'post_2026-02-25',
            'activityCount': 2,
            'createdAt': '2026-02-25T09:00:00Z',
            'updatedAt': '2026-02-25T10:00:00Z',
            'activities': [
              {
                'id': 'act_1',
                'type': 'post',
                'userId': 'john',
                'feeds': ['notifications:john'],
                'createdAt': '2026-02-25T10:00:00Z',
                'updatedAt': '2026-02-25T10:00:00Z',
              },
              {
                'id': 'act_2',
                'type': 'post',
                'userId': 'mary',
                'feeds': ['notifications:john'],
                'createdAt': '2026-02-25T09:00:00Z',
                'updatedAt': '2026-02-25T09:00:00Z',
              },
            ],
          },
          {
            'groupKey': 'comment_2026-02-25',
            'activityCount': 1,
            'createdAt': '2026-02-25T08:00:00Z',
            'updatedAt': '2026-02-25T08:00:00Z',
            'activities': [
              {
                'id': 'act_3',
                'type': 'comment',
                'userId': 'bob',
                'feeds': ['notifications:john'],
                'createdAt': '2026-02-25T08:00:00Z',
                'updatedAt': '2026-02-25T08:00:00Z',
              },
            ],
          },
        ],
        'unseenCount': 5,
        'unreadCount': 3,
      }, FastRelayActivity.fromJson);

      expect(page.isAggregated, isTrue);
      expect(page.groups, hasLength(2));
      expect(page.groups.first.groupKey, 'post_2026-02-25');
      expect(page.groups.first.activityCount, 2);
      expect(page.groups.first.activities, hasLength(2));
      expect(
        page.groups.first.updatedAt,
        DateTime.parse('2026-02-25T10:00:00Z'),
      );
      expect(page.unseenCount, 5);
      expect(page.unreadCount, 3);
      expect(page.data.map((a) => a.id), ['act_1', 'act_2', 'act_3']);
    });

    test('NotificationPage handles empty groups list', () {
      final page = NotificationPage<FastRelayActivity>.fromJson({
        'groups': const [],
        'unseenCount': 0,
        'unreadCount': 0,
      }, FastRelayActivity.fromJson);

      expect(page.isAggregated, isFalse);
      expect(page.groups, isEmpty);
      expect(page.data, isEmpty);
    });

    test('NotificationPage handles group with empty activities', () {
      final page = NotificationPage<FastRelayActivity>.fromJson({
        'groups': [
          {'groupKey': 'empty', 'activityCount': 0, 'activities': []},
        ],
        'unseenCount': 0,
        'unreadCount': 0,
      }, FastRelayActivity.fromJson);

      expect(page.groups, hasLength(1));
      expect(page.groups.first.activities, isEmpty);
      expect(page.data, isEmpty);
    });

    test('NotificationPage throws when both data and groups are missing', () {
      expect(
        () => NotificationPage<FastRelayActivity>.fromJson({
          'unseenCount': 1,
          'unreadCount': 1,
        }, FastRelayActivity.fromJson),
        throwsStateError,
      );
    });

    test('FastRelayActivity parses required and optional fields', () {
      final activity = FastRelayActivity.fromJson({
        'id': 'act_1',
        'type': 'post',
        'text': 'Hello world',
        'userId': 'john',
        'feeds': ['timeline:john'],
        'visibility': 'public',
        'custom': {'category': 'tech'},
        'popularity': 1.5,
        'reactionCounts': {'like': 10, 'wow': '2'},
        'commentCount': 7,
        'bookmarkCount': 4,
        'expiresAt': '2026-02-26T00:00:00Z',
        'createdAt': '2026-02-25T10:00:00Z',
        'updatedAt': '2026-02-25T10:05:00Z',
      });

      expect(activity.id, 'act_1');
      expect(activity.reactionCounts['like'], 10);
      expect(activity.reactionCounts['wow'], 2);
      expect(activity.custom?['category'], 'tech');
      expect(activity.expiresAt, DateTime.parse('2026-02-26T00:00:00Z'));
      expect(activity.ownReactions, isNull);
    });

    test('FastRelayActivity parses embedded ownReactions', () {
      final activity = FastRelayActivity.fromJson({
        'id': 'act_1',
        'type': 'post',
        'userId': 'john',
        'createdAt': '2026-02-25T10:00:00Z',
        'updatedAt': '2026-02-25T10:05:00Z',
        'ownReactions': [
          {
            'id': 'rxn_1',
            'activityId': 'act_1',
            'userId': 'john',
            'type': 'like',
            'createdAt': '2026-02-25T10:01:00Z',
          },
        ],
      });

      expect(activity.ownReactions, hasLength(1));
      expect(activity.ownReactions!.first.type, 'like');
    });

    test('activity, comment, and reaction parse embedded user objects', () {
      final userJson = {
        'id': 'john',
        'displayName': 'John Doe',
        'profileData': {'avatarUrl': 'https://example.com/a.png'},
        'role': 'user',
        'createdAt': '2026-02-25T10:00:00Z',
        'updatedAt': '2026-02-25T10:00:00Z',
      };

      final activity = FastRelayActivity.fromJson({
        'id': 'act_1',
        'type': 'post',
        'userId': 'john',
        'user': userJson,
        'createdAt': '2026-02-25T10:00:00Z',
        'updatedAt': '2026-02-25T10:00:00Z',
      });
      final comment = FastRelayComment.fromJson({
        'id': 'cmt_1',
        'activityId': 'act_1',
        'userId': 'john',
        'user': userJson,
        'text': 'Nice',
        'createdAt': '2026-02-25T10:00:00Z',
        'updatedAt': '2026-02-25T10:00:00Z',
      });
      final reaction = FastRelayReaction.fromJson({
        'id': 'rxn_1',
        'activityId': 'act_1',
        'userId': 'john',
        'user': userJson,
        'type': 'like',
        'createdAt': '2026-02-25T10:00:00Z',
      });

      expect(activity.user?.displayName, 'John Doe');
      expect(
        activity.user?.profileData?['avatarUrl'],
        'https://example.com/a.png',
      );
      expect(comment.user?.displayName, 'John Doe');
      expect(reaction.user?.displayName, 'John Doe');
      expect(activity.toJson()['user'], isNotNull);
    });

    test('comment parses custom payload with attachments', () {
      final comment = FastRelayComment.fromJson({
        'id': 'cmt_1',
        'activityId': 'act_1',
        'userId': 'john',
        'text': '',
        'custom': {
          'attachments': [
            {'type': 'image', 'imageUrl': 'https://example.com/img.jpg'},
          ],
        },
        'createdAt': '2026-02-25T10:00:00Z',
        'updatedAt': '2026-02-25T10:00:00Z',
      });

      final attachments = comment.custom?['attachments'] as List?;
      expect(attachments, hasLength(1));
      expect(
        (attachments?.first as Map)['imageUrl'],
        'https://example.com/img.jpg',
      );
      expect(comment.toJson()['custom'], isNotNull);
    });

    test('comment custom is null when absent', () {
      final comment = FastRelayComment.fromJson({
        'id': 'cmt_1',
        'activityId': 'act_1',
        'userId': 'john',
        'text': 'Nice',
        'createdAt': '2026-02-25T10:00:00Z',
        'updatedAt': '2026-02-25T10:00:00Z',
      });

      expect(comment.custom, isNull);
    });

    test('user is null when payload not enriched', () {
      final activity = FastRelayActivity.fromJson({
        'id': 'act_1',
        'type': 'post',
        'userId': 'john',
        'createdAt': '2026-02-25T10:00:00Z',
        'updatedAt': '2026-02-25T10:00:00Z',
      });
      final reaction = FastRelayReaction.fromJson({
        'id': 'rxn_1',
        'activityId': 'act_1',
        'userId': 'john',
        'type': 'like',
        'createdAt': '2026-02-25T10:00:00Z',
      });

      expect(activity.user, isNull);
      expect(reaction.user, isNull);
    });

    test('FastRelayPoll parses user vote payload', () {
      final poll = FastRelayPoll.fromJson({
        'id': 'poll_1',
        'question': 'Best language?',
        'options': [
          {'id': 'opt_1', 'text': 'Dart', 'voteCount': 2},
          {'id': 'opt_2', 'text': 'Kotlin', 'voteCount': 1},
        ],
        'totalVotes': 3,
        'userVote': {'optionId': 'opt_1'},
        'isClosed': false,
      });

      expect(poll.options, hasLength(2));
      expect(poll.userVote, 'opt_1');
      expect(poll.hasVoted, isTrue);
    });

    test('FastRelayUser initials prefer displayName, then id', () {
      final withName = FastRelayUser.fromJson({
        'id': 'john_doe',
        'displayName': 'John Doe',
        'createdAt': '2026-02-25T10:00:00Z',
        'updatedAt': '2026-02-25T10:00:00Z',
      });
      final withoutName = FastRelayUser.fromJson({
        'id': 'alice',
        'createdAt': '2026-02-25T10:00:00Z',
        'updatedAt': '2026-02-25T10:00:00Z',
      });

      expect(withName.initials, 'JD');
      expect(withoutName.initials, 'A');
    });
  });
}
