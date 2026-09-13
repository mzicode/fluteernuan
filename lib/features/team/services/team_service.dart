import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/api/api_client.dart';

class TeamStats {
  final int total;
  final int level1;
  final int level2;
  final int level3;
  final int verified;
  final int unverified;

  const TeamStats({
    this.total = 0,
    this.level1 = 0,
    this.level2 = 0,
    this.level3 = 0,
    this.verified = 0,
    this.unverified = 0,
  });

  factory TeamStats.fromJson(Map<String, dynamic> json) {
    int value(String key) => int.tryParse(json[key]?.toString() ?? '') ?? 0;

    return TeamStats(
      total: value('total'),
      level1: value('level_1'),
      level2: value('level_2'),
      level3: value('level_3'),
      verified: value('verified'),
      unverified: value('unverified'),
    );
  }

  int countForLevel(int level) {
    switch (level) {
      case 1:
        return level1;
      case 2:
        return level2;
      case 3:
        return level3;
      default:
        return 0;
    }
  }
}

class TeamPerson {
  final String uuid;
  final String yixinId;
  final String nickname;
  final String avatar;

  const TeamPerson({
    this.uuid = '',
    this.yixinId = '',
    this.nickname = '',
    this.avatar = '',
  });

  factory TeamPerson.fromJson(Map<String, dynamic> json) {
    final rawAvatar = json['avatar']?.toString().trim() ?? '';
    return TeamPerson(
      uuid: json['uuid']?.toString() ?? '',
      yixinId: (json['yixin_id'] ?? json['short_id'])?.toString().trim() ?? '',
      nickname: json['nickname']?.toString().trim() ?? '',
      avatar: rawAvatar.isEmpty ? '' : ApiConfig.getMediaUrl(rawAvatar),
    );
  }
}

class ReferralProfile {
  final String yixinId;
  final String inviteCode;
  final String inviteParameter;
  final TeamPerson? parent;

  const ReferralProfile({
    this.yixinId = '',
    this.inviteCode = '',
    this.inviteParameter = '',
    this.parent,
  });

  factory ReferralProfile.fromJson(Map<String, dynamic> json) {
    final rawParent = json['parent'];
    return ReferralProfile(
      yixinId: (json['yixin_id'] ?? json['code'] ?? json['invite_code'])
              ?.toString()
              .trim() ??
          '',
      inviteCode: json['invite_code']?.toString().trim() ?? '',
      inviteParameter: json['invite_parameter']?.toString().trim() ?? '',
      parent: rawParent is Map
          ? TeamPerson.fromJson(Map<String, dynamic>.from(rawParent))
          : null,
    );
  }
}

class TeamMember extends TeamPerson {
  final String id;
  final String joinedAt;
  final String registeredAt;
  final String realNameStatus;
  final int level;

  const TeamMember({
    this.id = '',
    super.uuid,
    super.yixinId,
    super.nickname,
    super.avatar,
    this.joinedAt = '',
    this.registeredAt = '',
    this.realNameStatus = 'unsubmitted',
    this.level = 1,
  });

  factory TeamMember.fromJson(Map<String, dynamic> json) {
    final person = TeamPerson.fromJson(json);
    return TeamMember(
      id: json['id']?.toString() ?? '',
      uuid: person.uuid,
      yixinId: person.yixinId,
      nickname: person.nickname,
      avatar: person.avatar,
      joinedAt: json['joined_at']?.toString() ?? '',
      registeredAt: json['registered_at']?.toString() ?? '',
      realNameStatus:
          json['real_name_status']?.toString().trim().toLowerCase() ??
              'unsubmitted',
      level: int.tryParse(json['level']?.toString() ?? '') ?? 1,
    );
  }
}

class TeamMemberPage {
  final List<TeamMember> members;
  final int total;
  final int page;
  final int pageSize;

  const TeamMemberPage({
    this.members = const [],
    this.total = 0,
    this.page = 1,
    this.pageSize = 20,
  });

  factory TeamMemberPage.fromJson(dynamic data) {
    final map = data is Map ? Map<String, dynamic>.from(data) : null;
    final rawList = map?['list'] ?? map?['items'] ?? map?['data'] ?? data;
    final list = rawList is List ? rawList : const <dynamic>[];
    int value(String key, int fallback) =>
        int.tryParse(map?[key]?.toString() ?? '') ?? fallback;

    return TeamMemberPage(
      members: list
          .whereType<Map>()
          .map((item) => TeamMember.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false),
      total: value('total', list.length),
      page: value('page', 1),
      pageSize: value('page_size', 20),
    );
  }
}

class TeamService {
  final ApiClient _api;

  TeamService(this._api);

  Future<ApiResponse<ReferralProfile>> getReferralProfile() {
    return _api.get<ReferralProfile>(
      '/referral/profile',
      fromJson: (data) =>
          ReferralProfile.fromJson(Map<String, dynamic>.from(data as Map)),
    );
  }

  Future<ApiResponse<TeamStats>> getStats() {
    return _api.get<TeamStats>(
      '/team/stats',
      fromJson: (data) =>
          TeamStats.fromJson(Map<String, dynamic>.from(data as Map)),
    );
  }

  Future<ApiResponse<TeamMemberPage>> getMembers({
    required int level,
    int page = 1,
    int pageSize = 20,
  }) {
    return _api.get<TeamMemberPage>(
      '/team/members',
      queryParameters: {
        'level': level,
        'page': page,
        'page_size': pageSize,
      },
      fromJson: TeamMemberPage.fromJson,
    );
  }
}

final teamServiceProvider = Provider<TeamService>((ref) {
  return TeamService(ref.watch(apiClientProvider));
});
