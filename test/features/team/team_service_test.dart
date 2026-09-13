import 'package:flutter_test/flutter_test.dart';
import 'package:customer/features/team/services/team_service.dart';

void main() {
  test('team stats parses three levels and verification totals', () {
    final stats = TeamStats.fromJson(const {
      'total': 12,
      'level_1': 3,
      'level_2': 4,
      'level_3': 5,
      'verified': 7,
      'unverified': 5,
    });

    expect(stats.total, 12);
    expect(stats.countForLevel(1), 3);
    expect(stats.countForLevel(2), 4);
    expect(stats.countForLevel(3), 5);
    expect(stats.verified, 7);
  });

  test('member page accepts the documented page envelope', () {
    final page = TeamMemberPage.fromJson(const {
      'list': [
        {
          'id': 1,
          'uuid': 'member-1',
          'short_id': 100000123,
          'nickname': '暖邻用户',
          'real_name_status': 'approved',
          'level': 2,
        }
      ],
      'total': 1,
      'page': 1,
      'page_size': 20,
    });

    expect(page.total, 1);
    expect(page.members.single.yixinId, '100000123');
    expect(page.members.single.level, 2);
    expect(page.members.single.realNameStatus, 'approved');
  });

  test('referral profile treats Nuanlin ID as the personal invite code', () {
    final profile = ReferralProfile.fromJson(const {
      'code': '100000123',
      'invite_code': '100000123',
      'yixin_id': '100000123',
      'parent': {
        'uuid': 'parent-1',
        'yixin_id': 100000001,
        'nickname': '邀请人',
      },
    });

    expect(profile.yixinId, '100000123');
    expect(profile.inviteCode, '100000123');
    expect(profile.inviteParameter, isEmpty);
    expect(profile.parent?.yixinId, '100000001');
  });

  test('referral profile parses the new invite parameter fields', () {
    final profile = ReferralProfile.fromJson(const {
      'invite_code': '100020',
      'invite_parameter': '100020',
    });

    expect(profile.inviteCode, '100020');
    expect(profile.inviteParameter, '100020');
  });
}
