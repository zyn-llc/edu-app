import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../auth/auth_controller.dart';

/// Lug'at kartochkalari — `/v1/vocab`.
///
/// Kontrakt: `backend/app/api/v1/vocab.py`. Takrorlash jadvali SERVERDA
/// hisoblanadi (SM-2, `services/srs.py`) — klient faqat bahoni yuboradi.
/// Ikki joyda ikki xil jadval bo'lsa, ular albatta ajralib ketardi va
/// o'quvchi so'zni noto'g'ri kunda ko'rardi.

/// Nimani bilishini aytadigan uchta tugma.
///
/// SM-2 0..5 bahoni kutadi, lekin odamdan olti darajali baho so'rash —
/// o'ylantiradigan va sekinlashtiradigan ish. Uchta tugma yetarli va
/// ularning har biri aniq bitta SM-2 bahosiga tushadi.
enum RecallGrade {
  forgot(0),
  hard(3),
  easy(5);

  const RecallGrade(this.value);
  final int value;
}

class VocabLanguage {
  final String code;
  final String nameUz;
  final String nameRu;
  final int vocabCount;

  const VocabLanguage({
    required this.code,
    required this.nameUz,
    required this.nameRu,
    required this.vocabCount,
  });

  factory VocabLanguage.fromJson(Map<String, dynamic> j) => VocabLanguage(
        code: j['code'] as String,
        nameUz: j['name_uz'] as String,
        nameRu: j['name_ru'] as String,
        vocabCount: (j['vocab_count'] as num?)?.toInt() ?? 0,
      );

  String name(String lang) => lang == 'ru' ? nameRu : nameUz;
}

class VocabTopic {
  final String topic;
  final int count;

  const VocabTopic({required this.topic, required this.count});

  factory VocabTopic.fromJson(Map<String, dynamic> j) => VocabTopic(
        topic: j['topic'] as String,
        count: (j['count'] as num?)?.toInt() ?? 0,
      );
}

class VocabEntry {
  final String id;
  final String language;

  /// Ko'rsatiladigan shakl. Nemis oti uchun artikl bilan ("der Tisch") —
  /// SERVER yasaydi, chunki aks holda har bir ekran o'zicha yasardi va
  /// bittasi albatta unutardi.
  final String display;

  final String lemma;
  final String? ipa;
  final String? pos;
  final String? topic;
  final String cefrLevel;
  final String? article;
  final int? freqRank;
  final String? trUz;
  final String? trRu;
  final String? trEn;
  final bool inDeck;
  final String? state;

  const VocabEntry({
    required this.id,
    required this.language,
    required this.display,
    required this.lemma,
    required this.ipa,
    required this.pos,
    required this.topic,
    required this.cefrLevel,
    required this.article,
    required this.freqRank,
    required this.trUz,
    required this.trRu,
    required this.trEn,
    required this.inDeck,
    required this.state,
  });

  factory VocabEntry.fromJson(Map<String, dynamic> j) => VocabEntry(
        id: j['id'] as String,
        language: j['language'] as String,
        display: j['display'] as String,
        lemma: j['lemma'] as String,
        ipa: j['ipa'] as String?,
        pos: j['pos'] as String?,
        topic: j['topic'] as String?,
        cefrLevel: j['cefr_level'] as String? ?? 'A1',
        article: j['article'] as String?,
        freqRank: (j['freq_rank'] as num?)?.toInt(),
        trUz: j['tr_uz'] as String?,
        trRu: j['tr_ru'] as String?,
        trEn: j['tr_en'] as String?,
        inDeck: j['in_deck'] == true,
        state: j['state'] as String?,
      );

  /// Kartochkaning orqa tomoni — interfeys tiliga qarab.
  ///
  /// Nemis lug'atida `ru` va `en` tarjimalari MANBADA YO'Q (2 950 tadan
  /// hech birida), shuning uchun bo'sh qolganda o'zbekchaga tushadi. Aks
  /// holda rus interfeysidagi o'quvchi bo'sh kartochka ko'rardi.
  String? translation(String uiLang) {
    final ru = (trRu ?? '').trim();
    final uz = (trUz ?? '').trim();
    final en = (trEn ?? '').trim();
    if (uiLang == 'ru') {
      if (ru.isNotEmpty) return ru;
      if (uz.isNotEmpty) return uz;
      return en.isEmpty ? null : en;
    }
    if (uz.isNotEmpty) return uz;
    if (ru.isNotEmpty) return ru;
    return en.isEmpty ? null : en;
  }
}

class VocabStats {
  final int deckSize;
  final int learning;
  final int review;
  final int mastered;
  final int dueToday;

  const VocabStats({
    required this.deckSize,
    required this.learning,
    required this.review,
    required this.mastered,
    required this.dueToday,
  });

  static const empty = VocabStats(
      deckSize: 0, learning: 0, review: 0, mastered: 0, dueToday: 0);

  factory VocabStats.fromJson(Map<String, dynamic> j) => VocabStats(
        deckSize: (j['deck_size'] as num?)?.toInt() ?? 0,
        learning: (j['learning'] as num?)?.toInt() ?? 0,
        review: (j['review'] as num?)?.toInt() ?? 0,
        mastered: (j['mastered'] as num?)?.toInt() ?? 0,
        dueToday: (j['due_today'] as num?)?.toInt() ?? 0,
      );

  /// 0..1. Bo'sh to'plamda 0 — nolga bo'lish emas.
  double get masteredShare => deckSize == 0 ? 0 : mastered / deckSize;
}

class ReviewResult {
  final String entryId;
  final String state;
  final String dueOn;
  final int intervalDays;
  final int reviewedToday;
  final int coinsAwarded;

  const ReviewResult({
    required this.entryId,
    required this.state,
    required this.dueOn,
    required this.intervalDays,
    required this.reviewedToday,
    required this.coinsAwarded,
  });

  factory ReviewResult.fromJson(Map<String, dynamic> j) => ReviewResult(
        entryId: j['entry_id'] as String,
        state: j['state'] as String? ?? 'learning',
        dueOn: j['due_on'] as String? ?? '',
        intervalDays: (j['interval_days'] as num?)?.toInt() ?? 1,
        reviewedToday: (j['reviewed_today'] as num?)?.toInt() ?? 0,
        coinsAwarded: (j['coins_awarded'] as num?)?.toInt() ?? 0,
      );
}

// --------------------------------------------------------------------------- //
//  Repository + providers                                                      //
// --------------------------------------------------------------------------- //
class VocabQuery {
  final String language;
  final String? level;
  final String? topic;
  final String? search;

  const VocabQuery({
    required this.language,
    this.level,
    this.topic,
    this.search,
  });

  VocabQuery copyWith({
    String? language,
    String? level,
    String? topic,
    String? search,
    bool clearLevel = false,
    bool clearTopic = false,
  }) =>
      VocabQuery(
        language: language ?? this.language,
        level: clearLevel ? null : (level ?? this.level),
        topic: clearTopic ? null : (topic ?? this.topic),
        search: search ?? this.search,
      );

  @override
  bool operator ==(Object other) =>
      other is VocabQuery &&
      other.language == language &&
      other.level == level &&
      other.topic == topic &&
      other.search == search;

  @override
  int get hashCode => Object.hash(language, level, topic, search);
}

class VocabRepository {
  final Ref ref;
  VocabRepository(this.ref);

  Future<List<VocabLanguage>> languages() async {
    final res = await ref.read(dioProvider).get('/v1/vocab/languages');
    return [
      for (final e in (res.data as Map<String, dynamic>)['items'] as List)
        VocabLanguage.fromJson(e as Map<String, dynamic>)
    ];
  }

  Future<List<VocabTopic>> topics(String language, {String? level}) async {
    final res = await ref.read(dioProvider).get('/v1/vocab/topics',
        queryParameters: {
          'language': language,
          if (level != null) 'level': level,
        });
    return [
      for (final e in (res.data as Map<String, dynamic>)['items'] as List)
        VocabTopic.fromJson(e as Map<String, dynamic>)
    ];
  }

  Future<List<VocabEntry>> entries(VocabQuery q,
      {int limit = 50, int offset = 0}) async {
    final res = await ref.read(dioProvider).get('/v1/vocab/entries',
        queryParameters: {
          'language': q.language,
          if (q.level != null) 'level': q.level,
          if (q.topic != null) 'topic': q.topic,
          if ((q.search ?? '').trim().isNotEmpty) 'q': q.search!.trim(),
          'limit': limit,
          'offset': offset,
        });
    return [
      for (final e in (res.data as Map<String, dynamic>)['items'] as List)
        VocabEntry.fromJson(e as Map<String, dynamic>)
    ];
  }

  Future<({int added, int already})> addToDeck(List<String> ids) async {
    final res = await ref
        .read(dioProvider)
        .post('/v1/vocab/deck', data: {'entry_ids': ids});
    final j = res.data as Map<String, dynamic>;
    return (
      added: (j['added'] as num?)?.toInt() ?? 0,
      already: (j['already'] as num?)?.toInt() ?? 0
    );
  }

  Future<void> removeFromDeck(String entryId) =>
      ref.read(dioProvider).delete('/v1/vocab/deck/$entryId');

  Future<List<VocabEntry>> due(String? language, {int limit = 20}) async {
    final res = await ref.read(dioProvider).get('/v1/vocab/review/due',
        queryParameters: {
          if (language != null) 'language': language,
          'limit': limit,
        });
    return [
      for (final e in (res.data as Map<String, dynamic>)['items'] as List)
        VocabEntry.fromJson(e as Map<String, dynamic>)
    ];
  }

  Future<ReviewResult> review(String entryId, RecallGrade grade) async {
    final res = await ref.read(dioProvider).post('/v1/vocab/review',
        data: {'entry_id': entryId, 'grade': grade.value});
    return ReviewResult.fromJson(res.data as Map<String, dynamic>);
  }

  Future<VocabStats> stats(String? language) async {
    final res = await ref.read(dioProvider).get('/v1/vocab/stats',
        queryParameters: {if (language != null) 'language': language});
    return VocabStats.fromJson(res.data as Map<String, dynamic>);
  }
}

final vocabRepositoryProvider =
    Provider<VocabRepository>((ref) => VocabRepository(ref));

final vocabLanguagesProvider =
    FutureProvider<List<VocabLanguage>>((ref) async {
  // Ro'yxat auth'ga bog'liq emas, lekin chiqib-kirganda yangilanishi kerak.
  ref.watch(authControllerProvider);
  return ref.read(vocabRepositoryProvider).languages();
});

/// Tanlangan til. `null` — hali tanlanmagan.
final selectedLanguageProvider = StateProvider<String?>((_) => null);

final vocabTopicsProvider =
    FutureProvider.family<List<VocabTopic>, String>((ref, language) async {
  ref.watch(authControllerProvider);
  return ref.read(vocabRepositoryProvider).topics(language);
});

final vocabEntriesProvider =
    FutureProvider.family<List<VocabEntry>, VocabQuery>((ref, q) async {
  ref.watch(authControllerProvider);
  return ref.read(vocabRepositoryProvider).entries(q);
});

final vocabStatsProvider =
    FutureProvider.family<VocabStats, String?>((ref, language) async {
  ref.watch(authControllerProvider);
  return ref.read(vocabRepositoryProvider).stats(language);
});

final vocabDueProvider =
    FutureProvider.family<List<VocabEntry>, String?>((ref, language) async {
  ref.watch(authControllerProvider);
  return ref.read(vocabRepositoryProvider).due(language);
});
