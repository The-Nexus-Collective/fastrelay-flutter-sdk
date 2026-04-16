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
