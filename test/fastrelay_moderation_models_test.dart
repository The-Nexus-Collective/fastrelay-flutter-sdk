import 'package:fastrelay_feed_sdk/fastrelay_feed_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('moderation models', () {
    test('FastRelayModerationFlag parses resolved fields', () {
      final flag = FastRelayModerationFlag.fromJson({
        'id': 'flag_1',
        'reporterId': 'user_alice',
        'targetType': 'activity',
        'targetId': 'act_1',
        'reason': 'spam',
        'description': 'Looks bad',
        'status': 'reviewed',
        'resolvedBy': 'mod_jane',
        'resolvedAt': '2026-03-19T11:00:00Z',
        'createdAt': '2026-03-19T10:00:00Z',
      });

      expect(flag.id, 'flag_1');
      expect(flag.resolvedBy, 'mod_jane');
      expect(flag.resolvedAt, DateTime.parse('2026-03-19T11:00:00Z'));
    });

    test('ban and mute models parse optional moderation fields', () {
      final ban = FastRelayUserBan.fromJson({
        'id': 'ban_1',
        'userId': 'user_bob',
        'type': 'shadow',
        'reason': 'abuse',
        'bannedBy': 'mod_jane',
        'expiresAt': '2026-03-20T10:00:00Z',
        'createdAt': '2026-03-19T10:00:00Z',
      });
      final mute = FastRelayUserMute.fromJson({
        'id': 'mut_1',
        'muterId': 'user_alice',
        'mutedUserId': 'user_bob',
        'type': 'personal',
        'createdAt': '2026-03-19T10:00:00Z',
      });

      expect(ban.userId, 'user_bob');
      expect(ban.expiresAt, DateTime.parse('2026-03-20T10:00:00Z'));
      expect(mute.muterId, 'user_alice');
      expect(mute.mutedUserId, 'user_bob');
    });

    test('blocklist and regex filter models parse rule configuration', () {
      final blocklist = FastRelayBlocklist.fromJson({
        'id': 'blk_1',
        'name': 'Profanity',
        'words': ['foo', 'bar'],
        'behavior': 'block',
        'active': true,
        'createdAt': '2026-03-19T10:00:00Z',
        'updatedAt': '2026-03-19T10:05:00Z',
      });
      final regexFilter = FastRelayRegexFilter.fromJson({
        'id': 'rgx_1',
        'name': 'URLs',
        'pattern': 'https?://',
        'behavior': 'flag',
        'active': false,
        'createdAt': '2026-03-19T10:00:00Z',
        'updatedAt': '2026-03-19T10:05:00Z',
      });

      expect(blocklist.words, ['foo', 'bar']);
      expect(blocklist.behavior, 'block');
      expect(regexFilter.pattern, 'https?://');
      expect(regexFilter.active, isFalse);
    });

    test('content check model parses match metadata', () {
      final result = FastRelayContentCheck.fromJson({
        'action': 'flag',
        'matches': [
          {
            'ruleType': 'regex',
            'ruleId': 'rgx_1',
            'ruleName': 'URLs',
            'behavior': 'flag',
          },
        ],
      });

      expect(result.action, 'flag');
      expect(result.matches, hasLength(1));
      expect(result.matches.first.ruleType, 'regex');
      expect(result.matches.first.ruleName, 'URLs');
    });
  });
}
