import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../auth/auth_controller.dart';

class LbEntry {
  final int rank;
  final String userId;
  final String? displayName;
  final String? regionCode;
  final int score;
  final bool isMe;

  /// Avatar palitrasi indeksi (0..11). `null` — foydalanuvchi tanlamagan,
  /// klient ism hash'idan barqaror rang oladi.
  final int? avatarColor;

  LbEntry(this.rank, this.userId, this.displayName, this.regionCode, this.score,
      this.isMe, {this.avatarColor});

  factory LbEntry.fromJson(Map<String, dynamic> j) => LbEntry(
        (j['rank'] as num).toInt(),
        j['user_id'] as String,
        j['display_name'] as String?,
        j['region_code'] as String?,
        (j['score'] as num).toInt(),
        j['is_me'] as bool? ?? false,
        avatarColor: (j['avatar_color'] as num?)?.toInt(),
      );
}

class LeaderboardData {
  final String scope;
  final String? key;
  final List<LbEntry> entries;
  final LbEntry? me;
  final int totalRanked;
  LeaderboardData(this.scope, this.key, this.entries, this.me, this.totalRanked);

  factory LeaderboardData.fromJson(Map<String, dynamic> j) => LeaderboardData(
        j['scope'] as String,
        j['key'] as String?,
        [for (final e in (j['entries'] as List)) LbEntry.fromJson(e)],
        j['me'] == null
            ? null
            : LbEntry.fromJson(j['me'] as Map<String, dynamic>),
        (j['total_ranked'] as num?)?.toInt() ?? 0,
      );

  /// True when [me] exists but isn't already shown in [entries] (off-page).
  bool get meIsOffPage =>
      me != null && !entries.any((e) => e.userId == me!.userId);
}

class LeaderboardRepository {
  final Ref ref;
  LeaderboardRepository(this.ref);

  Future<LeaderboardData> fetch(String scope, String? key, {int limit = 50}) async {
    final params = <String, dynamic>{'scope': scope, 'limit': limit};
    if (key != null) params['key'] = key;
    final res =
        await ref.read(dioProvider).get('/v1/leaderboard', queryParameters: params);
    return LeaderboardData.fromJson(res.data as Map<String, dynamic>);
  }
}

final leaderboardRepositoryProvider =
    Provider<LeaderboardRepository>((ref) => LeaderboardRepository(ref));

/// Keyed by (scope, key). Re-fetches on login/logout so "you" highlighting and
/// the personal standing update.
final leaderboardProvider = FutureProvider.family<LeaderboardData,
    ({String scope, String? key})>((ref, args) async {
  ref.watch(authControllerProvider);
  return ref.read(leaderboardRepositoryProvider).fetch(args.scope, args.key);
});
