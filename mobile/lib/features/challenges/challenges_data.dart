import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../auth/auth_controller.dart';
import '../quiz/quiz_data.dart' show Question;

// ---------------- Models ----------------
class Challenge {
  final String id;
  final String code;
  final String role; // creator | opponent
  final String subjectId;
  final int? grade;
  final int questionCount;
  final int stake;
  final String status; // open | active | done | cancelled | expired
  final int? myScore;
  final int? theirScore;
  final bool? iWon; // null until done; null on draw when done
  final bool hasOpponent;
  final String? winnerId;

  Challenge({
    required this.id,
    required this.code,
    required this.role,
    required this.subjectId,
    required this.grade,
    required this.questionCount,
    required this.stake,
    required this.status,
    required this.myScore,
    required this.theirScore,
    required this.iWon,
    required this.hasOpponent,
    required this.winnerId,
  });

  factory Challenge.fromJson(Map<String, dynamic> j) => Challenge(
        id: j['id'] as String,
        code: j['code'] as String,
        role: j['role'] as String,
        subjectId: j['subject_id'] as String,
        grade: (j['grade'] as num?)?.toInt(),
        questionCount: (j['question_count'] as num).toInt(),
        stake: (j['stake'] as num).toInt(),
        status: j['status'] as String,
        myScore: (j['my_score'] as num?)?.toInt(),
        theirScore: (j['their_score'] as num?)?.toInt(),
        iWon: j['i_won'] as bool?,
        hasOpponent: j['has_opponent'] as bool? ?? false,
        winnerId: j['winner_id'] as String?,
      );

  bool get isDraw => status == 'done' && winnerId == null;

  /// I still have to play: active and my score not in yet.
  bool get needsMyPlay => status == 'active' && myScore == null;

  /// I played, opponent hasn't.
  bool get waitingForThem => status == 'active' && myScore != null;
}

class ChallengeSubmitResult {
  final int yourScore;
  final int maxScore;
  final String status;
  final String? winnerId;
  final int pot;
  ChallengeSubmitResult(
      this.yourScore, this.maxScore, this.status, this.winnerId, this.pot);

  factory ChallengeSubmitResult.fromJson(Map<String, dynamic> j) {
    final settled = j['settled'] as Map<String, dynamic>?;
    return ChallengeSubmitResult(
      (j['your_score'] as num).toInt(),
      (j['max_score'] as num).toInt(),
      j['status'] as String,
      settled?['winner_id'] as String?,
      (settled?['pot'] as num?)?.toInt() ?? 0,
    );
  }
}

class CoinInfo {
  final int balance;
  final int perCorrect;
  final int perWrong;
  final int dailyBonus;
  final int perAd;
  final int adsLeftToday;
  CoinInfo(this.balance, this.perCorrect, this.perWrong, this.dailyBonus,
      this.perAd, this.adsLeftToday);

  factory CoinInfo.fromJson(Map<String, dynamic> j) => CoinInfo(
        (j['balance'] as num).toInt(),
        (j['per_correct'] as num).toInt(),
        (j['per_wrong'] as num).toInt(),
        (j['daily_bonus'] as num).toInt(),
        (j['per_ad'] as num).toInt(),
        (j['ads_left_today'] as num).toInt(),
      );
}

// ---------------- Repository ----------------
class ChallengeRepository {
  final Ref ref;
  ChallengeRepository(this.ref);

  Future<List<Challenge>> myChallenges() async {
    final res = await ref.read(dioProvider).get('/v1/challenges');
    return [
      for (final e in (res.data['items'] as List))
        Challenge.fromJson(e as Map<String, dynamic>)
    ];
  }

  Future<Challenge> create({
    required String subjectId,
    int? grade,
    required int questionCount,
    required int stake,
  }) async {
    final res = await ref.read(dioProvider).post('/v1/challenges', data: {
      'subject_id': subjectId,
      if (grade != null) 'grade': grade,
      'question_count': questionCount,
      'stake': stake,
    });
    return Challenge.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Challenge> join(String code) async {
    final res = await ref
        .read(dioProvider)
        .post('/v1/challenges/join', data: {'code': code});
    return Challenge.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> cancel(String id) async {
    await ref.read(dioProvider).post('/v1/challenges/$id/cancel');
  }

  Future<List<Question>> questions(String id, String lang) async {
    final res = await ref
        .read(dioProvider)
        .get('/v1/challenges/$id/questions', queryParameters: {'lang': lang});
    return [
      for (final q in (res.data['items'] as List))
        Question.fromJson(q as Map<String, dynamic>)
    ];
  }

  /// Batch submit: the whole answer sheet in one call. During a bet the server
  /// gives no per-question feedback (anti answer-leak); corrections come back
  /// only in this response.
  Future<ChallengeSubmitResult> submit(
      String id, Map<String, Map<String, dynamic>> answers) async {
    final res = await ref.read(dioProvider).post('/v1/challenges/$id/submit',
        data: {
          'answers': [
            for (final e in answers.entries)
              {'question_id': e.key, 'payload': e.value}
          ]
        });
    return ChallengeSubmitResult.fromJson(res.data as Map<String, dynamic>);
  }

  Future<CoinInfo> coins() async {
    final res = await ref.read(dioProvider).get('/v1/me/coins');
    return CoinInfo.fromJson(res.data as Map<String, dynamic>);
  }

  Future<CoinInfo> watchAd() async {
    await ref.read(dioProvider).post('/v1/me/coins/ad-reward', data: {});
    return coins();
  }
}

final challengeRepositoryProvider =
    Provider<ChallengeRepository>((ref) => ChallengeRepository(ref));

/// My challenge list — refreshes on login/logout.
final myChallengesProvider = FutureProvider<List<Challenge>>((ref) async {
  ref.watch(authControllerProvider);
  return ref.read(challengeRepositoryProvider).myChallenges();
});

/// Coin balance + economy numbers — refreshes on login/logout.
final coinInfoProvider = FutureProvider<CoinInfo>((ref) async {
  ref.watch(authControllerProvider);
  return ref.read(challengeRepositoryProvider).coins();
});
