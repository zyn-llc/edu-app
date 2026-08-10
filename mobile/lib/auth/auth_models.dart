/// DTOs mirroring the backend auth/leaderboard schemas.
library;

class TokenPair {
  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  TokenPair(this.accessToken, this.refreshToken, this.expiresIn);

  factory TokenPair.fromJson(Map<String, dynamic> j) => TokenPair(
        j['access_token'] as String,
        j['refresh_token'] as String,
        (j['expires_in'] as num?)?.toInt() ?? 900,
      );
}

class UserMe {
  final String id;
  final String role; // student | parent | admin
  final String? phone;

  final String? username;
  final String? displayName;
  final String? regionCode;
  final int? grade;
  final String? locale;

  final int? avatarColor;

  final bool? tgNotifications;

  UserMe({
    required this.id,
    required this.role,
    this.phone,
    this.username,
    this.displayName,
    this.regionCode,
    this.grade,
    this.locale,
    this.avatarColor,
    this.tgNotifications,
  });

  bool get isParent => role == 'parent';
  bool get isStudent => role == 'student';

  factory UserMe.fromJson(Map<String, dynamic> j) => UserMe(
        id: j['id'] as String,
        role: (j['role'] as String?) ?? 'student',
        phone: j['phone'] as String?,
        username: j['username'] as String?,
        displayName: j['display_name'] as String?,
        regionCode: j['region_code'] as String?,
        grade: (j['grade'] as num?)?.toInt(),
        locale: j['locale'] as String?,
        avatarColor: (j['avatar_color'] as num?)?.toInt(),
        tgNotifications: j['tg_notifications'] as bool?,
      );
}

class DayStat {
  final DateTime date;
  final int answered;
  final int correct;
  final bool isToday;

  const DayStat({
    required this.date,
    this.answered = 0,
    this.correct = 0,
    this.isToday = false,
  });

  bool get isActive => answered > 0;

  factory DayStat.fromJson(Map<String, dynamic> j) => DayStat(
        // `DateTime.parse` YYYY-MM-DD ni mahalliy yarim tun deb o'qiydi —
        date: DateTime.tryParse(j['date'] as String? ?? '') ?? DateTime.now(),
        answered: (j['answered'] as num?)?.toInt() ?? 0,
        correct: (j['correct'] as num?)?.toInt() ?? 0,
        isToday: j['is_today'] as bool? ?? false,
      );
}

class Progress {
  final int xp;
  final int level;
  final int streakDays;
  final int answered;
  final int correct;
  final double accuracy; // 0..1

  /// "bajarildi / bajarilmadi" ni fanlarning `lastPracticedAt` idan taxmin
  final int answeredToday;
  final int correctToday;
  final int xpToday;

  final int answered7d;
  final int correct7d;
  final double accuracy7d; // 0..1
  final int xp7d;
  final int activeDays7d;

  final List<DayStat> week;

  const Progress({
    this.xp = 0,
    this.level = 1,
    this.streakDays = 0,
    this.answered = 0,
    this.correct = 0,
    this.accuracy = 0,
    this.answeredToday = 0,
    this.correctToday = 0,
    this.xpToday = 0,
    this.answered7d = 0,
    this.correct7d = 0,
    this.accuracy7d = 0,
    this.xp7d = 0,
    this.activeDays7d = 0,
    this.week = const [],
  });

  double? get accuracyToday =>
      answeredToday == 0 ? null : correctToday / answeredToday;

  factory Progress.fromJson(Map<String, dynamic> j) => Progress(
        xp: (j['xp'] as num?)?.toInt() ?? 0,
        level: (j['level'] as num?)?.toInt() ?? 1,
        streakDays: (j['streak_days'] as num?)?.toInt() ?? 0,
        answered: (j['answered'] as num?)?.toInt() ?? 0,
        correct: (j['correct'] as num?)?.toInt() ?? 0,
        accuracy: (j['accuracy'] as num?)?.toDouble() ?? 0,
        answeredToday: (j['answered_today'] as num?)?.toInt() ?? 0,
        correctToday: (j['correct_today'] as num?)?.toInt() ?? 0,
        xpToday: (j['xp_today'] as num?)?.toInt() ?? 0,
        answered7d: (j['answered_7d'] as num?)?.toInt() ?? 0,
        correct7d: (j['correct_7d'] as num?)?.toInt() ?? 0,
        accuracy7d: (j['accuracy_7d'] as num?)?.toDouble() ?? 0,
        xp7d: (j['xp_7d'] as num?)?.toInt() ?? 0,
        activeDays7d: (j['active_days_7d'] as num?)?.toInt() ?? 0,
        week: [
          for (final d in (j['week'] as List? ?? const []))
            DayStat.fromJson(d as Map<String, dynamic>),
        ],
      );
}

/// Response of GET /v1/me.
class MeOverview {
  final UserMe user;
  final Progress progress;
  final int? rank;
  final int coins;
  MeOverview(this.user, this.progress, this.rank, this.coins);

  factory MeOverview.fromJson(Map<String, dynamic> j) => MeOverview(
        UserMe.fromJson(j['user'] as Map<String, dynamic>),
        Progress.fromJson(j['progress'] as Map<String, dynamic>),
        (j['rank'] as num?)?.toInt(),
        (j['coins'] as num?)?.toInt() ?? 0,
      );
}

class Region {
  final String code;
  final String uz;
  final String ru;
  Region(this.code, this.uz, this.ru);
  factory Region.fromJson(Map<String, dynamic> j) =>
      Region(j['code'] as String, j['uz'] as String, j['ru'] as String);
  String name(String lang) => lang == 'ru' ? ru : uz;
}

/// One topic's mastery (distinct-question accuracy).
class TopicStat {
  final String topicCode;
  final String name;
  final int answered;
  final int correct;
  final double accuracy; // 0..1
  TopicStat(this.topicCode, this.name, this.answered, this.correct,
      this.accuracy);
  factory TopicStat.fromJson(Map<String, dynamic> j) => TopicStat(
        j['topic_code'] as String,
        j['name'] as String? ?? '',
        (j['answered'] as num?)?.toInt() ?? 0,
        (j['correct'] as num?)?.toInt() ?? 0,
        (j['accuracy'] as num?)?.toDouble() ?? 0,
      );
}

class Analysis {
  final List<TopicStat> topics;
  Analysis(this.topics);
  factory Analysis.fromJson(Map<String, dynamic> j) => Analysis([
        for (final t in (j['topics'] as List? ?? []))
          TopicStat.fromJson(t as Map<String, dynamic>),
      ]);

  /// Weakest topics with enough data to be meaningful (>=3 distinct questions).
  List<TopicStat> get weakest {
    final eligible = topics.where((t) => t.answered >= 3).toList()
      ..sort((a, b) => a.accuracy.compareTo(b.accuracy));
    return eligible.take(3).toList();
  }

  List<TopicStat> get strongest {
    final eligible = topics.where((t) => t.answered >= 3).toList()
      ..sort((a, b) => b.accuracy.compareTo(a.accuracy));
    return eligible.take(3).toList();
  }
}
