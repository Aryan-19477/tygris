/// Ranger / Team roster entities.
library;

enum RangerRole { ranger, seniorRanger, teamLead }

extension RangerRoleX on RangerRole {
  static RangerRole fromName(String? name) => RangerRole.values.firstWhere(
        (v) => v.name == name,
        orElse: () => RangerRole.ranger,
      );
}

class Ranger {
  Ranger({
    required this.id,
    required this.name,
    required this.badgeId,
    required this.phone,
    required this.role,
    this.teamId,
    required this.avatarSeed,
  });

  final String id;
  final String name;
  final String badgeId;
  final String phone;
  final RangerRole role;
  final String? teamId;
  final String avatarSeed;

  Ranger copyWith({
    String? name,
    String? badgeId,
    String? phone,
    RangerRole? role,
    String? teamId,
  }) =>
      Ranger(
        id: id,
        name: name ?? this.name,
        badgeId: badgeId ?? this.badgeId,
        phone: phone ?? this.phone,
        role: role ?? this.role,
        teamId: teamId ?? this.teamId,
        avatarSeed: avatarSeed,
      );

  factory Ranger.fromJson(Map<String, dynamic> j) => Ranger(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        badgeId: j['badge_id'] as String? ?? '',
        phone: j['phone'] as String? ?? '',
        role: RangerRoleX.fromName(j['role'] as String?),
        teamId: j['team_id'] as String?,
        avatarSeed: j['avatar_seed'] as String? ?? (j['id'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'badge_id': badgeId,
        'phone': phone,
        'role': role.name,
        'team_id': teamId,
        'avatar_seed': avatarSeed,
      };
}

class Team {
  Team({
    required this.id,
    required this.name,
    required this.memberIds,
    required this.beatOrZone,
  });

  final String id;
  final String name;
  final List<String> memberIds;
  final String beatOrZone;

  factory Team.fromJson(Map<String, dynamic> j) => Team(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        memberIds: ((j['member_ids'] as List<dynamic>?) ?? [])
            .map((e) => e as String)
            .toList(),
        beatOrZone: j['beat_or_zone'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'member_ids': memberIds,
        'beat_or_zone': beatOrZone,
      };
}
