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

    test('mute model parses optional moderation fields', () {
      final mute = FastRelayUserMute.fromJson({
        'id': 'mut_1',
        'muterId': 'user_alice',
        'mutedUserId': 'user_bob',
        'type': 'personal',
        'createdAt': '2026-03-19T10:00:00Z',
      });

      expect(mute.muterId, 'user_alice');
      expect(mute.mutedUserId, 'user_bob');
    });
  });
}
