import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../auth/auth_controller.dart';

class Subject {
  final String id;
  final String code;
  final String name;
  final String? imageUrl;

  /// Bankdagi aktiv savollar soni.
  final int questionCount;

  /// Savoli bor bo'limlar soni.
  final int topicCount;

  /// Foydalanuvchi yechgan TURLI savollar soni (takror sanalmaydi).
  final int answered;
  final int correct;

  /// 0..1 — aniqlik (`correct / answered`), bank qamrovi EMAS.
  /// 5 700 savolli bankda 50 ta yechgan o'quvchiga 0.9% ko'rsatish
  /// ilova buzuq degan taassurot qoldiradi.
  final double accuracy;

  final DateTime? lastPracticedAt;

  const Subject({
    required this.id,
    required this.code,
    required this.name,
    this.imageUrl,
    this.questionCount = 0,
    this.topicCount = 0,
    this.answered = 0,
    this.correct = 0,
    this.accuracy = 0,
    this.lastPracticedAt,
  });

  /// Foydalanuvchi bu fanni boshlaganmi.
  bool get isStarted => answered > 0;

  factory Subject.fromJson(Map<String, dynamic> j) => Subject(
        id: j['id'] as String,
        code: j['code'] as String,
        name: j['name'] as String,
        imageUrl: resolveImage(j['image_url'] as String?),
        questionCount: (j['question_count'] as num?)?.toInt() ?? 0,
        topicCount: (j['topic_count'] as num?)?.toInt() ?? 0,
        answered: (j['answered'] as num?)?.toInt() ?? 0,
        correct: (j['correct'] as num?)?.toInt() ?? 0,
        accuracy: (j['accuracy'] as num?)?.toDouble() ?? 0,
        lastPracticedAt: j['last_practiced_at'] == null
            ? null
            : DateTime.tryParse(j['last_practiced_at'] as String)?.toLocal(),
      );
}

class SubjectsRepository {
  final Ref ref;
  SubjectsRepository(this.ref);

  Future<List<Subject>> fetchSubjects() async {
    final dio = ref.read(dioProvider);
    final res = await dio.get('/v1/subjects');
    final items = (res.data['items'] as List).cast<Map<String, dynamic>>();
    final list = items.map(Subject.fromJson).toList();
    // Savoli yo'q fanlar (kimyo, fizika — seed'da bor, kontent hali yo'q)
    // oxiriga suriladi. Ular ro'yxatdan olib tashlanmaydi: o'quvchi ular
    // rejada borligini ko'rishi kerak. Lekin ekranning eng ko'rinadigan
    // joyini egallamasligi ham kerak.
    list.sort((a, b) {
      final ae = a.questionCount <= 0 ? 1 : 0;
      final be = b.questionCount <= 0 ? 1 : 0;
      return ae != be ? ae - be : 0;
    });
    return list;
  }
}

final subjectsRepositoryProvider =
    Provider<SubjectsRepository>((ref) => SubjectsRepository(ref));

final subjectsProvider = FutureProvider<List<Subject>>((ref) async {
  // Til o'zgarsa — nomlar tarjimasi uchun.
  ref.watch(localeCodeProvider);
  // Kirish/chiqishda — endpoint endi shaxsiy progressni ham qaytaradi,
  // aks holda kirgandan keyin ham kartochkalar "0 yechilgan" bo'lib qolardi.
  ref.watch(authControllerProvider);
  return ref.read(subjectsRepositoryProvider).fetchSubjects();
});
