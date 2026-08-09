import 'dart:math';

import 'package:dio/dio.dart';

/// Serversiz demo rejimi.
///
///     flutter run -d chrome --dart-define=MOCK=true
///
/// Nega kerak: prezentatsiya, jyuri ko'rsatuvi yoki internetsiz sinov paytida
/// VPS, Postgres va Redis ishlamasligi mumkin. Bu rejimda butun backend
/// brauzer xotirasida yashaydi — hech qanday tarmoq so'rovi chiqmaydi.
///
/// MUHIM INVARIANT: javob kaliti (`_Q.correctKey`) hech qachon `/v1/questions`
/// javobida yuborilmaydi. Faqat `/v1/submissions` javobida
/// `correct_option_ids` sifatida qaytadi — real backenddagi qoida bilan bir xil.
/// Agar bu buzilsa, mock real serverdan "osonroq" bo'lib qoladi va klientdagi
/// xatoni yashiradi.
const kMockMode = bool.fromEnvironment('MOCK', defaultValue: false);

/// Dio zanjirining OXIRIGA qo'shiladi: undan oldingi interceptorlar
/// `Authorization` / `Accept-Language` sarlavhalarini qo'yib bo'lgan bo'ladi,
/// shuning uchun mock ularni real server kabi o'qiy oladi.
class MockInterceptor extends Interceptor {
  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    // Sun'iy kechikish: yuklanish indikatorlari real ko'rinsin va "bir zumda
    // paydo bo'lgan" UI holatlari sinovdan o'tsin.
    await Future<void>.delayed(const Duration(milliseconds: 220));
    try {
      final data = _MockServer.instance.handle(options);
      handler.resolve(Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
        data: data,
      ));
    } on _MockHttpError catch (e) {
      handler.reject(DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          requestOptions: options,
          statusCode: e.status,
          data: e.body,
        ),
      ));
    } catch (e) {
      // Mockdagi kutilmagan xato 500 bo'lib chiqsin. Aks holda istisno
      // interceptor ichida yo'qoladi va so'rov abadiy "yuklanmoqda" holatida
      // muzlab qoladi — sabab topish juda qiyin bo'lgan xato turi.
      handler.reject(DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          requestOptions: options,
          statusCode: 500,
          data: {'detail': 'mock_internal_error: $e'},
        ),
      ));
    }
  }
}

class _MockHttpError implements Exception {
  final int status;
  final Map<String, dynamic> body;
  _MockHttpError(this.status, String detail) : body = {'detail': detail};
}

// --------------------------------------------------------------------------- //
//  Server                                                                     //
// --------------------------------------------------------------------------- //

class _MockServer {
  static final _MockServer instance = _MockServer._();
  _MockServer._();

  final Random _rng = Random(42);
  int _seq = 0;
  String _id(String prefix) => '$prefix-${++_seq}';

  // --- sessiya holati ---
  String _pendingRole = 'student';
  String? _pendingPhone;
  String? _tgNonce;
  DateTime? _tgStartedAt;

  _User? _user;

  // --- o'yin holati ---
  int _xp = 0;
  int _answered = 0;
  int _correct = 0;
  int _coins = 120;

  /// Real `config.py` bilan bir xil bo'lishi SHART — aks holda demo
  /// foydalanuvchiga noto'g'ri raqamlarni o'rgatadi.
  ///   xp_per_point=10, xp_per_level=100, coins_per_correct=5,
  ///   coins_per_wrong_penalty=1, coins_per_ad=15, ads_per_day_cap=3
  static const _xpPerPoint = 10;
  static const _xpPerLevel = 100;
  static const _coinsPerCorrect = 5;
  static const _coinsWrongPenalty = 1;
  static const _coinsPerAd = 15;
  static const _adsPerDayCap = 3;

  int _adsLeftToday = _adsPerDayCap;
  final Set<String> _seenQuestionIds = {};

  /// Fan kodi -> shu fan bo'yicha shaxsiy natija. `/v1/subjects` javobidagi
  /// `answered`/`correct`/`accuracy`/`last_practiced_at` shu yerdan keladi.
  final Map<String, _SubjectProgress> _subjectProgress = {};

  /// Savol id -> fan kodi. `_grade()` da qaysi fan hisobiga yozishni bilish
  /// uchun; `_Q` da fan maydoni yo'q, bank esa fan bo'yicha guruhlangan.
  late final Map<String, String> _subjectOfQuestion = {
    for (final e in _bank.entries)
      for (final q in e.value) q.id: e.key,
  };

  /// Tanga faqat BIR MARTA beriladi (har savol uchun). Serverda buni
  /// `coin_transactions(user_id, ref_id)` ustidagi qisman unique indeks
  /// ta'minlaydi — `services/coins.try_award_quiz`. Mock ham xuddi shunday,
  /// aks holda bitta savolni qayta-qayta yechib tanga "farm" qilish mumkin
  /// bo'lib qolardi va demo real xatti-harakatdan uzoqlashardi.
  final Set<String> _rewardedQuestionIds = {};

  final List<_Ch> _challenges = [];
  final List<Map<String, dynamic>> _notes = [];

  /// Ota-ona paneli: kod kiritilganidan keyingina farzand ko'rinadi.
  bool _hasLinkedChild = false;

  /// Har `/v1/submissions` uchun savol id → to'g'ri kalit izlash jadvali.
  late final Map<String, _Q> _byId = {
    for (final list in _bank.values)
      for (final q in list) q.id: q,
  };

  // ------------------------------------------------------------------- //
  //  Router                                                             //
  // ------------------------------------------------------------------- //
  dynamic handle(RequestOptions o) {
    final m = o.method.toUpperCase();
    final p = o.path;
    final q = o.queryParameters;
    final body = (o.data is Map) ? (o.data as Map).cast<String, dynamic>() : const <String, dynamic>{};
    // Mehmon (`X-Debug-User-Id`) ham sessiya hisoblanadi — real backendda
    // ham mehmon mashq qila oladi va javoblari serverda saqlanadi. Aks holda
    // demo paytida tanga balansi va bellashuv ro'yxati kirmasdan turib 401
    // qaytarardi.
    final authed = o.headers['Authorization'] != null ||
        o.headers['X-Debug-User-Id'] != null;

    // --- auth ---
    if (m == 'GET' && p == '/v1/auth/methods') {
      // Demoda to'rtala yo'l ham ochiq — sinovchi hammasini ko'rib chiqsin.
      return {
        'password': true,
        'phone': true,
        'telegram': true,
        'invite': true,
        'telegram_bot_username': 'topagonuzbot',
      };
    }

    if (m == 'POST' && p == '/v1/auth/otp/request') {
      _pendingPhone = body['phone'] as String?;
      _pendingRole = (body['role'] as String?) ?? 'student';
      return {
        'retry_after_seconds': 60,
        'expires_in_seconds': 300,
        // Mock rejimida kod doim ko'rinadi — sinovchi SMS kutmaydi.
        'debug_code': '111111',
      };
    }

    if (m == 'POST' && p == '/v1/auth/otp/verify') {
      final code = (body['code'] as String?)?.trim();
      if (code != '111111') {
        throw _MockHttpError(400, 'invalid_code');
      }
      _login(
        role: _pendingRole,
        phone: body['phone'] as String? ?? _pendingPhone,
        displayName: body['display_name'] as String?,
        regionCode: body['region_code'] as String?,
        grade: (body['grade'] as num?)?.toInt(),
      );
      return _tokens();
    }

    if (m == 'POST' && p == '/v1/auth/invite') {
      final code = (body['code'] as String?) ?? '';
      if (code.length < 4) throw _MockHttpError(404, 'invite_not_found');
      _login(
        role: 'student',
        displayName: body['display_name'] as String?,
        grade: (body['grade'] as num?)?.toInt(),
      );
      return _tokens();
    }

    // --- parol yo'li ---
    // Demoda haqiqiy parol tekshiruvi yo'q: mock'da baza ham, hash ham yo'q.
    // Maqsad — oqimni (forma -> token -> dashboard) sinab ko'rish.
    if (m == 'POST' && p == '/v1/auth/register') {
      final name = (body['username'] as String?)?.trim() ?? '';
      if (name.length < 3) throw _MockHttpError(400, 'bad_username');
      // "band" holatini ham ko'rsata olish uchun bitta nom ataylab olingan.
      if (name.toLowerCase() == 'admin') {
        throw _MockHttpError(409, 'username_taken');
      }
      if ((body['password'] as String? ?? '').length < 6) {
        throw _MockHttpError(400, 'weak_password');
      }
      _login(
        role: 'student',
        username: name,
        displayName: (body['display_name'] as String?)?.trim().isNotEmpty == true
            ? body['display_name'] as String
            : name,
        grade: (body['grade'] as num?)?.toInt(),
      );
      return _tokens();
    }

    if (m == 'POST' && p == '/v1/auth/login') {
      final name = (body['username'] as String?)?.trim() ?? '';
      final pw = body['password'] as String? ?? '';
      // Demoda 6+ belgili istalgan parol o'tadi; qisqasi 401 beradi, ya'ni
      // xato holatini ham ko'rish mumkin.
      if (name.length < 3 || pw.length < 6) {
        throw _MockHttpError(401, 'bad_credentials');
      }
      _login(role: 'student', username: name, displayName: name);
      return _tokens();
    }

    if (m == 'GET' && p == '/v1/auth/username-free') {
      final name = (q['username'] as String?)?.trim() ?? '';
      final free = name.length >= 3 && name.toLowerCase() != 'admin';
      return {'username': name, 'free': free};
    }

    if (m == 'POST' && p == '/v1/auth/password') {
      final u = _require(authed);
      if ((body['password'] as String? ?? '').length < 6) {
        throw _MockHttpError(400, 'weak_password');
      }
      final name = (body['username'] as String?)?.trim();
      if (u.username == null && (name == null || name.length < 3)) {
        throw _MockHttpError(400, 'username_required');
      }
      if (name != null && name.isNotEmpty) u.username = name;
      // Real server bu yerda eski sessiyalarni bekor qilib, YANGI juftlik
      // beradi — mock ham shuni qaytaradi, aks holda klientdagi "yangi
      // tokenni saqlash" yo'li mockda umuman sinalmasdi.
      return {'ok': true, 'username': u.username, ..._tokens()};
    }

    if (m == 'POST' && p == '/v1/auth/telegram/start') {
      _tgNonce = _id('nonce');
      // Sanoq BIRINCHI so'rovdan boshlanadi (`poll`), havola olinganidan emas.
      // Aks holda foydalanuvchi havolani 5 soniyadan ko'proq o'qib tursa,
      // birinchi so'rovning o'ziyoq "kirdi" deb qaytarardi.
      _tgStartedAt = null;
      return {
        'nonce': _tgNonce,
        'deep_link': 'https://t.me/topagonuzbot?start=$_tgNonce',
        'expires_in_seconds': 600,
        // Real serverda bu kod bot tugmasida ham chiqadi va foydalanuvchi
        // ikkalasini solishtiradi. Mockda bot yo'q, lekin kod ko'rsatiladi —
        // aks holda ekranning bu qismi demoda umuman sinalmasdi.
        'confirm_code': 'A7K2',
      };
    }

    if (m == 'POST' && p == '/v1/auth/telegram/poll') {
      if (body['nonce'] != _tgNonce) throw _MockHttpError(410, 'nonce_expired');
      // Demo: birinchi so'rovdan 5 soniya o'tgach "foydalanuvchi botda Start
      // bosdi" deb hisoblanadi.
      _tgStartedAt ??= DateTime.now();
      final elapsed = DateTime.now().difference(_tgStartedAt!);
      if (elapsed.inSeconds < 5) return {'status': 'pending'};
      _login(role: 'student', displayName: 'Telegram sinovchi');
      return {'status': 'ok', ..._tokens()};
    }

    if (m == 'POST' && p == '/v1/auth/refresh') {
      if (_user == null) throw _MockHttpError(401, 'invalid_refresh');
      return _tokens();
    }

    if (m == 'POST' && p == '/v1/auth/logout') {
      _user = null;
      return {'ok': true};
    }

    if (m == 'PATCH' && p == '/v1/auth/me') {
      final u = _require(authed);
      if (body['display_name'] != null) u.displayName = body['display_name'] as String;
      if (body['region_code'] != null) u.regionCode = body['region_code'] as String;
      if (body['grade'] != null) u.grade = (body['grade'] as num).toInt();
      if (body['avatar_color'] != null) {
        u.avatarColor = (body['avatar_color'] as num).toInt();
      }
      if (body['tg_notifications'] != null) {
        u.tgNotifications = body['tg_notifications'] as bool;
      }
      return u.toJson();
    }

    // --- me ---
    if (m == 'GET' && p == '/v1/me') {
      final u = _require(authed);
      return {
        'user': u.toJson(),
        'progress': _progress(),
        'rank': 1 + (2000 - _xp).clamp(0, 4200) ~/ 12,
        'coins': _coins,
      };
    }

    if (m == 'GET' && p == '/v1/me/analysis') {
      _require(authed);
      return {'topics': _topicStats()};
    }

    if (m == 'GET' && p == '/v1/me/coins') {
      _require(authed);
      return _coinInfo();
    }

    if (m == 'POST' && p == '/v1/me/coins/ad-reward') {
      _require(authed);
      if (_adsLeftToday <= 0) throw _MockHttpError(429, 'ad_limit_reached');
      _adsLeftToday -= 1;
      _coins += _coinsPerAd;
      return _coinInfo();
    }

    // --- katalog ---
    if (m == 'GET' && p == '/v1/regions') {
      return {'regions': _regions};
    }

    if (m == 'GET' && p == '/v1/subjects') {
      // MUHIM: shakl `app/api/v1/content.py` dagi `list_subjects` bilan
      // AYNAN bir xil bo'lishi kerak. Ilgari bu yerda bitta `progress`
      // (double) qaytardi — `Subject.fromJson` esa yassi `question_count`,
      // `answered`, `accuracy` maydonlarini o'qiydi. Natijada MOCK rejimda
      // har bir fan `questionCount == 0` bo'lib "Savollar tayyorlanmoqda"
      // ko'rinardi.
      return {
        'items': [
          for (final s in _subjects)
            {
              'id': s.code,
              'code': s.code,
              'icon': null,
              'name': s.name,
              'image_url': null,
              'question_count': s.count,
              'topic_count': _topicsOf(s.code).length,
              'answered': _progressOf(s.code).answered,
              'correct': _progressOf(s.code).correct,
              'accuracy': _progressOf(s.code).accuracy,
              'last_practiced_at':
                  _progressOf(s.code).lastAt?.toIso8601String(),
            }
        ]
      };
    }

    final catalogMatch =
        RegExp(r'^/v1/subjects/([^/]+)/catalog$').firstMatch(p);
    if (m == 'GET' && catalogMatch != null) {
      return _catalog(catalogMatch.group(1)!);
    }

    if (m == 'GET' && p == '/v1/questions') {
      final subjectId = q['subject_id'] as String? ?? 'geografiya';
      final limit = (q['limit'] as num?)?.toInt() ?? 10;
      return {'items': _pickQuestions(subjectId, limit)};
    }

    if (m == 'POST' && p == '/v1/submissions') {
      return _grade(body);
    }

    // --- leaderboard ---
    if (m == 'GET' && p == '/v1/leaderboard') {
      return _leaderboard(
        q['scope'] as String? ?? 'global',
        q['key'] as String?,
        (q['limit'] as num?)?.toInt() ?? 50,
      );
    }

    // --- bellashuv ---
    if (m == 'GET' && p == '/v1/challenges') {
      _require(authed);
      return {'items': [for (final c in _challenges.reversed) c.toJson(_user!.id)]};
    }

    if (m == 'POST' && p == '/v1/challenges') {
      final u = _require(authed);
      final stake = (body['stake'] as num?)?.toInt() ?? 10;
      if (stake > _coins) throw _MockHttpError(400, 'insufficient_coins');
      _coins -= stake;
      final c = _Ch(
        id: _id('ch'),
        code: _code(),
        creatorId: u.id,
        subjectId: body['subject_id'] as String? ?? 'geografiya',
        grade: (body['grade'] as num?)?.toInt(),
        questionCount: (body['question_count'] as num?)?.toInt() ?? 5,
        stake: stake,
      );
      _challenges.add(c);
      return c.toJson(u.id);
    }

    if (m == 'POST' && p == '/v1/challenges/join') {
      final u = _require(authed);
      final code = (body['code'] as String?)?.toUpperCase();
      final c = _challenges.where((e) => e.code == code).firstOrNull;
      if (c == null) throw _MockHttpError(404, 'challenge_not_found');
      c.forceOpponent();
      return c.toJson(u.id);
    }

    final cancelMatch = RegExp(r'^/v1/challenges/([^/]+)/cancel$').firstMatch(p);
    if (m == 'POST' && cancelMatch != null) {
      final u = _require(authed);
      final c = _challenge(cancelMatch.group(1)!);
      if (c.effectiveStatus != 'open') throw _MockHttpError(409, 'already_started');
      c.cancelled = true;
      _coins += c.stake; // garov qaytariladi
      return c.toJson(u.id);
    }

    final chQMatch = RegExp(r'^/v1/challenges/([^/]+)/questions$').firstMatch(p);
    if (m == 'GET' && chQMatch != null) {
      _require(authed);
      final c = _challenge(chQMatch.group(1)!);
      return {'items': _pickQuestions(c.subjectId, c.questionCount)};
    }

    final chSubMatch = RegExp(r'^/v1/challenges/([^/]+)/submit$').firstMatch(p);
    if (m == 'POST' && chSubMatch != null) {
      final u = _require(authed);
      final c = _challenge(chSubMatch.group(1)!);
      final answers = (body['answers'] as List?) ?? const [];
      var score = 0;
      for (final a in answers) {
        final map = (a as Map).cast<String, dynamic>();
        final qq = _byId[map['question_id']];
        if (qq == null) continue;
        final payload = (map['payload'] as Map?)?.cast<String, dynamic>() ?? {};
        final ids = (payload['option_ids'] as List?)?.cast<String>() ?? const [];
        if (ids.length == 1 && ids.first == qq.correctKey) score++;
      }
      return c.settle(u.id, score, answers.length, onCoins: (d) => _coins += d);
    }

    // --- eslatmalar ---
    if (m == 'GET' && p == '/v1/notes') {
      _require(authed);
      final qid = q['question_id'] as String?;
      return {
        'items': [
          for (final n in _notes.reversed)
            if (qid == null || n['question_id'] == qid) n
        ]
      };
    }

    if (m == 'POST' && p == '/v1/notes') {
      _require(authed);
      final n = <String, dynamic>{
        'id': _id('note'),
        'title': body['title'],
        'body': body['body'],
        'question_id': body['question_id'],
        'subject_id': body['subject_id'],
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      _notes.add(n);
      return n;
    }

    final noteMatch = RegExp(r'^/v1/notes/([^/]+)$').firstMatch(p);
    if (noteMatch != null) {
      _require(authed);
      final id = noteMatch.group(1)!;
      final n = _notes.where((e) => e['id'] == id).firstOrNull;
      if (n == null) throw _MockHttpError(404, 'note_not_found');
      if (m == 'PATCH') {
        if (body['body'] != null) n['body'] = body['body'];
        if (body['title'] != null) n['title'] = body['title'];
        n['updated_at'] = DateTime.now().toUtc().toIso8601String();
        return n;
      }
      if (m == 'DELETE') {
        _notes.remove(n);
        return {'ok': true};
      }
    }

    // --- e'lonlar / fikr-mulohaza ---
    if (m == 'GET' && p == '/v1/announcements') {
      return {'items': _announcements};
    }

    if (m == 'POST' && p == '/v1/feedback') {
      return {'ok': true};
    }

    // --- ota-ona ---
    if (m == 'POST' && p == '/v1/parent/link-code') {
      _require(authed);
      return {'code': _code(), 'expires_in_seconds': 600};
    }

    if (m == 'POST' && p == '/v1/parent/link') {
      _require(authed);
      final code = (body['code'] as String?) ?? '';
      if (code.length < 4) throw _MockHttpError(404, 'link_code_not_found');
      _hasLinkedChild = true;
      return {'ok': true};
    }

    if (m == 'GET' && p == '/v1/parent/children') {
      _require(authed);
      // Demo haqiqiy oqimni takrorlasin: kod kiritilmaguncha ro'yxat bo'sh.
      // Ilgari bu yerda hamma vaqt tayyor bola qaytardi va "kod kiriting"
      // qadamini sinab ko'rib bo'lmasdi.
      return {'children': _hasLinkedChild ? _children : const []};
    }

    final childMatch =
        RegExp(r'^/v1/parent/children/([^/]+)/analysis$').firstMatch(p);
    if (m == 'GET' && childMatch != null) {
      _require(authed);
      return {'topics': _topicStats(seedShift: 3)};
    }

    throw _MockHttpError(404, 'mock: yo\'nalish qo\'llab-quvvatlanmaydi — $m $p');
  }

  // ------------------------------------------------------------------- //
  //  Yordamchilar                                                       //
  // ------------------------------------------------------------------- //

  /// Web'da sahifa yangilanganda tokenlar `SharedPreferences` da qoladi,
  /// lekin mock xotirasi bo'shaydi. Sarlavhada token bor ekan — sessiyani
  /// tiklaymiz, aks holda demo har `F5` da tizimdan chiqib ketardi.
  _User _require(bool authed) {
    if (!authed) throw _MockHttpError(401, 'not_authenticated');
    _user ??= _User(
      id: 'mock-student-1',
      role: 'student',
      phone: '+998901234567',
      displayName: "Sinov o'quvchi",
      regionCode: 'TOSHKENT_SHAHRI',
      grade: 9,
    );
    return _user!;
  }

  void _login({
    required String role,
    String? phone,
    String? username,
    String? displayName,
    String? regionCode,
    int? grade,
  }) {
    _user = _User(
      id: role == 'parent' ? 'mock-parent-1' : 'mock-student-1',
      role: role,
      phone: phone,
      username: username,
      displayName: displayName ??
          (role == 'parent' ? 'Sinov ota-ona' : "Sinov o'quvchi"),
      regionCode: regionCode ?? 'TOSHKENT_SHAHRI',
      grade: grade ?? (role == 'parent' ? null : 9),
    );
  }

  Map<String, dynamic> _tokens() => {
        'access_token': 'mock-access-${DateTime.now().millisecondsSinceEpoch}',
        'refresh_token': 'mock-refresh-${DateTime.now().millisecondsSinceEpoch}',
        'expires_in': 900,
      };

  /// `YYYY-MM-DD` — server `week[].date` bilan bir xil format.
  static String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Demo uchun oldingi 6 kunning javob soni (eng eskisidan boshlab).
  ///
  /// Bu YAGONA o'ylab topilgan raqam guruhi va u faqat MOCK rejimida
  /// ko'rinadi (`--dart-define=MOCK=true`). Sababi: haftalik chiziq va
  /// "Bu hafta" yig'indisi bo'sh bo'lsa demo ularni umuman ko'rsatmasdi va
  /// ekranni tekshirib bo'lmasdi. Ikkita nol kun ATAYLAB qoldirilgan —
  /// bo'sh doira ham ko'rinishi kerak.
  static const _mockWeekPast = [8, 0, 14, 20, 0, 6];

  Map<String, dynamic> _progress() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Bugungi kun — sessiyadagi HAQIQIY javoblar (mock ichida sessiya =
    // bitta kun).
    final week = <Map<String, dynamic>>[
      for (var i = 0; i < _mockWeekPast.length; i++)
        {
          'date': _ymd(today.subtract(
              Duration(days: _mockWeekPast.length - i))),
          'answered': _mockWeekPast[i],
          'correct': (_mockWeekPast[i] * 0.8).round(),
          'is_today': false,
        },
      {
        'date': _ymd(today),
        'answered': _answered,
        'correct': _correct,
        'is_today': true,
      },
    ];

    var answered7d = 0;
    var correct7d = 0;
    var activeDays = 0;
    for (final d in week) {
      final a = d['answered'] as int;
      answered7d += a;
      correct7d += d['correct'] as int;
      if (a > 0) activeDays += 1;
    }

    return {
      'xp': _xp,
      'level': 1 + _xp ~/ _xpPerLevel,
      'streak_days': 3,
      'answered': _answered,
      'correct': _correct,
      'accuracy': _answered == 0 ? 0.0 : _correct / _answered,
      'answered_today': _answered,
      'correct_today': _correct,
      'xp_today': _xp,
      'answered_7d': answered7d,
      'correct_7d': correct7d,
      'accuracy_7d': answered7d == 0 ? 0.0 : correct7d / answered7d,
      // Serverda XP faqat BIRINCHI to'g'ri javob uchun beriladi; demoda
      // o'tgan kunlar uchun shu qoidani taxminan takrorlaymiz.
      'xp_7d': correct7d * _xpPerPoint,
      'active_days_7d': activeDays,
      'week': week,
    };
  }

  Map<String, dynamic> _coinInfo() => {
        'balance': _coins,
        'per_correct': _coinsPerCorrect,
        'per_wrong': _coinsWrongPenalty,
        'daily_bonus': 10,
        'per_ad': _coinsPerAd,
        'ads_left_today': _adsLeftToday,
      };

  String _code() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(6, (_) => alphabet[_rng.nextInt(alphabet.length)]).join();
  }

  _Ch _challenge(String id) {
    final c = _challenges.where((e) => e.id == id).firstOrNull;
    if (c == null) throw _MockHttpError(404, 'challenge_not_found');
    return c;
  }

  // --- savollar ---

  List<Map<String, dynamic>> _pickQuestions(String subjectId, int limit) {
    final bank = _bank[subjectId] ?? _bank['geografiya']!;
    // Ko'rilmaganlarini oldinga qo'yamiz — demo paytida bir xil savol
    // qayta-qayta chiqmasin.
    final fresh = bank.where((q) => !_seenQuestionIds.contains(q.id)).toList();

    // Dublikatsiz to'plash: `fresh` yetmasa bankning boshidan davom etamiz,
    // lekin bitta mashqda AYNI savol ikki marta chiqmasligi kerak — bu demo
    // paytida darrov ko'zga tashlanadi.
    final out = <_Q>[];
    for (final q in [...fresh, ...bank]) {
      if (out.length >= limit) break;
      if (out.any((e) => e.id == q.id)) continue;
      out.add(q);
    }
    for (final q in out) {
      _seenQuestionIds.add(q.id);
    }
    // Bank tugab qolsa (barcha savol ko'rilgan) — hisobni tozalaymiz.
    if (fresh.length <= limit) _seenQuestionIds.clear();

    return [for (final q in out) q.toPublicJson()];
  }

  /// Baholash. Javob kaliti FAQAT shu yerda ochiladi.
  Map<String, dynamic> _grade(Map<String, dynamic> body) {
    final qid = body['question_id'] as String?;
    final q = _byId[qid];
    if (q == null) throw _MockHttpError(404, 'question_not_found');

    final payload = (body['payload'] as Map?)?.cast<String, dynamic>() ?? {};
    final ids = (payload['option_ids'] as List?)?.cast<String>() ?? const [];
    final isCorrect = ids.length == 1 && ids.first == q.correctKey;

    _answered += 1;

    // Fan bo'yicha hisob — dashboard kartochkalari shu raqamlarni ko'rsatadi.
    final subjectCode = _subjectOfQuestion[q.id];
    if (subjectCode != null) {
      final sp = _progressOf(subjectCode);
      sp.answered += 1;
      if (isCorrect) sp.correct += 1;
      sp.lastAt = DateTime.now();
    }

    // Mukofot hisoboti — serverdagi `GradeResult` bilan bir xil maydonlar,
    // aks holda MOCK rejimida "+10 XP" chipi hech qachon ko'rinmaydi va
    // demo haqiqiy ilovadan farq qilib qoladi.
    int xpAwarded = 0;
    int coinsAwarded = 0;
    int coinsPenalty = 0;
    String reason;

    if (isCorrect) {
      _correct += 1;
      // XP ham, tanga ham faqat birinchi to'g'ri javobda (`try_award_quiz`).
      if (_rewardedQuestionIds.add(q.id)) {
        _xp += _xpPerPoint;
        _coins += _coinsPerCorrect;
        xpAwarded = _xpPerPoint;
        coinsAwarded = _coinsPerCorrect;
        reason = 'ok';
      } else {
        reason = 'repeat';
      }
    } else {
      // Jarima 0 dan pastga tushmaydi — qarz UX aynan qiynalayotgan
      // o'quvchini jazolaydi, ular esa bizga eng kerakli auditoriya.
      // (`clamp()` ataylab ishlatilmadi: uning statik turi `num`.)
      final before = _coins;
      _coins -= _coinsWrongPenalty;
      if (_coins < 0) _coins = 0;
      coinsPenalty = before - _coins;
      reason = 'wrong';
    }

    return {
      'is_correct': isCorrect,
      'score': isCorrect ? 1 : 0,
      'max_score': 1,
      // Kalit va izoh FAQAT to'g'ri javobda — real backend bilan aynan bir
      // xil qoida. Aks holda mockda ishlaydigan ekran prodda boshqacha
      // ko'rinardi va noto'g'ri javob holati umuman sinalmasdi.
      'correct_option_ids': isCorrect ? [q.correctKey] : <String>[],
      'explanation': isCorrect ? q.explanation : null,
      'xp_awarded': xpAwarded,
      'coins_awarded': coinsAwarded,
      'coins_delta': coinsAwarded - coinsPenalty,
      'reward_reason': reason,
    };
  }

  /// Fan bo'yicha shaxsiy progress. Yo'q bo'lsa bo'sh yozuv yaratiladi —
  /// chaqiruv joyida `null` tekshiruvi kerak bo'lmasin.
  _SubjectProgress _progressOf(String code) =>
      _subjectProgress.putIfAbsent(code, () => _SubjectProgress());

  Map<String, dynamic> _catalog(String subjectId) {
    final total = _subjects
        .firstWhere((s) => s.code == subjectId,
            orElse: () => _subjects.first)
        .count;
    return {
      'grades': [
        for (var g = 5; g <= 11; g++) {'grade': g, 'count': (total / 7).round()}
      ],
      'exam_contexts': [
        {'code': 'maktab', 'count': (total * 0.6).round()},
        {'code': 'attestatsiya', 'count': (total * 0.25).round()},
        {'code': 'dtm', 'count': (total * 0.15).round()},
      ],
      'topics': [
        for (var i = 0; i < _topicsOf(subjectId).length; i++)
          {
            'id': 'topic-$subjectId-$i',
            'title': _topicsOf(subjectId)[i],
            'count': 40 + (i * 17) % 130,
          }
      ],
    };
  }

  List<Map<String, dynamic>> _topicStats({int seedShift = 0}) => [
        for (var i = 0; i < _topicNames.length; i++)
          {
            'topic_code': 'topic-$i',
            'name': _topicNames[i],
            'answered': 4 + (i * 3 + seedShift) % 14,
            'correct': 2 + (i * 2 + seedShift) % 9,
            'accuracy': (((i * 13 + seedShift * 7) % 60) + 35) / 100,
          }
      ];

  Map<String, dynamic> _leaderboard(String scope, String? key, int limit) {
    const names = [
      'Diyorbek', 'Malika', 'Javohir', 'Zilola', 'Sardor', 'Nilufar',
      'Bekzod', 'Gulnoza', 'Otabek', 'Shahzoda', 'Aziz', 'Kamola',
      'Jasur', 'Dilnoza', 'Ulug\'bek', 'Sevara', 'Temur', 'Robiya',
      'Farrux', 'Ozoda',
    ];
    final entries = <Map<String, dynamic>>[];
    for (var i = 0; i < limit && i < 50; i++) {
      entries.add({
        'rank': i + 1,
        'user_id': 'lb-$i',
        'display_name': '${names[i % names.length]} ${String.fromCharCode(65 + i % 26)}.',
        'region_code': _regions[i % _regions.length]['code'],
        'score': 4200 - i * 73 - (i * i) % 40,
        'is_me': false,
      });
    }
    final myRank = 1 + (2000 - _xp).clamp(0, 4200) ~/ 12;
    final me = _user == null
        ? null
        : {
            'rank': myRank,
            'user_id': _user!.id,
            'display_name': _user!.displayName,
            'region_code': _user!.regionCode,
            'score': _xp,
            'is_me': true,
          };
    return {
      'scope': scope,
      'key': key,
      'entries': entries,
      'me': me,
      'total_ranked': 1284,
    };
  }
}

// --------------------------------------------------------------------------- //
//  Modellar                                                                   //
// --------------------------------------------------------------------------- //

class _User {
  final String id;
  final String role;
  String? phone;
  String? username;
  String? displayName;
  String? regionCode;
  int? grade;
  int? avatarColor;
  /// `null` = tanlanmagan; server buni "yoqilgan" deb hisoblaydi.
  bool? tgNotifications;

  _User({
    required this.id,
    required this.role,
    this.phone,
    this.username,
    this.displayName,
    this.regionCode,
    this.grade,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'phone': phone,
        'username': username,
        'display_name': displayName,
        'region_code': regionCode,
        'grade': grade,
        'locale': 'uz-Latn',
        'avatar_color': avatarColor,
        'tg_notifications': tgNotifications,
      };
}

/// Bellashuv. Raqib **4 soniyadan keyin** avtomatik qo'shiladi — demo paytida
/// ikkinchi qurilma yoki ikkinchi akkaunt kerak bo'lmasin.
class _Ch {
  final String id;
  final String code;
  final String creatorId;
  final String subjectId;
  final int? grade;
  final int questionCount;
  final int stake;
  final DateTime createdAt = DateTime.now();

  bool cancelled = false;
  bool _opponentForced = false;
  int? myScore;
  int? theirScore;
  bool settled = false;

  _Ch({
    required this.id,
    required this.code,
    required this.creatorId,
    required this.subjectId,
    required this.grade,
    required this.questionCount,
    required this.stake,
  });

  bool get hasOpponent =>
      _opponentForced ||
      DateTime.now().difference(createdAt) >= const Duration(seconds: 4);

  void forceOpponent() => _opponentForced = true;

  String get effectiveStatus {
    if (cancelled) return 'cancelled';
    if (settled) return 'done';
    if (!hasOpponent) return 'open';
    return 'active';
  }

  String? get winnerId {
    if (!settled) return null;
    if (myScore! > theirScore!) return creatorId;
    if (myScore! < theirScore!) return 'mock-opponent-1';
    return null; // durang
  }

  Map<String, dynamic> toJson(String meId) => {
        'id': id,
        'code': code,
        'role': 'creator',
        'subject_id': subjectId,
        'grade': grade,
        'question_count': questionCount,
        'stake': stake,
        'status': effectiveStatus,
        'my_score': myScore,
        'their_score': theirScore,
        'i_won': settled ? (winnerId == null ? null : winnerId == meId) : null,
        'has_opponent': hasOpponent,
        'winner_id': winnerId,
      };

  Map<String, dynamic> settle(
    String meId,
    int score,
    int maxScore, {
    required void Function(int delta) onCoins,
  }) {
    myScore = score;
    // Raqib biroz zaifroq o'ynaydi: demo ko'pincha g'alaba bilan tugasin,
    // lekin har doim emas — durang va mag'lubiyat ham ko'rinishi kerak.
    //
    // `.toInt()` SHART: `num.clamp()` ning statik turi `num`, `int` emas —
    // `int?` maydonga to'g'ridan-to'g'ri berilsa kompilyatsiya xatosi bo'ladi.
    theirScore = (score - 1 + (DateTime.now().second % 3)).clamp(0, maxScore).toInt();
    settled = true;
    final pot = stake * 2;
    if (winnerId == meId) {
      onCoins(pot);
    } else if (winnerId == null) {
      onCoins(stake); // durang — garov qaytadi
    }
    return {
      'your_score': score,
      'max_score': maxScore,
      'status': 'done',
      'settled': {'winner_id': winnerId, 'pot': pot},
    };
  }
}

class _Q {
  final String id;
  final String stem;
  final List<String> options; // a, b, c, d tartibida
  final String correctKey;
  final String explanation;

  const _Q(this.id, this.stem, this.options, this.correctKey, this.explanation);

  /// Ommaviy proyeksiya — javob kaliti YO'Q.
  Map<String, dynamic> toPublicJson() => {
        'id': id,
        'type': 'single_choice',
        'stem': stem,
        'options': [
          for (var i = 0; i < options.length; i++)
            {'option_key': String.fromCharCode(97 + i), 'text': options[i]}
        ],
      };
}

class _Subject {
  final String code;
  final String name;
  final int count;
  const _Subject(this.code, this.name, this.count);
}

/// Bitta fan bo'yicha shaxsiy natija (mock sessiyasi davomida).
class _SubjectProgress {
  int answered = 0;
  int correct = 0;
  DateTime? lastAt;

  /// 0..1 — ANIQLIK (`correct / answered`), bank qamrovi emas. Serverdagi
  /// `content.py` bilan bir xil ta'rif.
  double get accuracy => answered == 0 ? 0.0 : correct / answered;
}

extension _FirstOrNullX<E> on Iterable<E> {
  /// `package:collection` ni pubspec'ga qo'shmaslik uchun. Nomi ataylab
  /// noyob (`_FirstOrNullX`) — kelajakda `collection` qo'shilsa ham
  /// `firstOrNull` bilan to'qnashmasin.
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}

// --------------------------------------------------------------------------- //
//  Ma'lumotlar                                                                //
// --------------------------------------------------------------------------- //

/// Savol sonlari REAL bankdan olingan (`D:\data_subjects\clean_data\*/core.json`,
/// `status == 'active'`), 2026-08-05 holati:
///
///   matematika 9 942 (1 655 mcq + 7 967 text_open + 317 proof_open)
///   geografiya 7 365 · ozbekiston_tarixi 2 420 · biologiya 1 658
///   ona_tili 834 · huquq 645 · jahon_tarixi 620      -> jami 23 484
///
/// Bazaga yuklanganda matematikaning `text_open` qismi `numeric` (2 924) va
/// `open_keyword` (895 active + 4 097 draft) ga bo'linadi, shuning uchun
/// matematikaning AKTIV soni ~5 450. Bu yerda aynan shu — bazadagi holat —
/// ko'rsatilgan, aks holda demo bankni bor-yo'g'idan katta ko'rsatardi.
/// 2026-08-05: sonlar PROD bazasidan olingan (`preflight.py` chiqishi),
/// ya'ni demo real ilova bilan bir xil raqamni ko'rsatadi. Jami 18 665 aktiv.
const _subjects = <_Subject>[
  _Subject('geografiya', 'Geografiya', 7169),
  _Subject('matematika', 'Matematika', 5453),
  _Subject('ozbekiston_tarixi', "O'zbekiston tarixi", 2415),
  _Subject('biologiya', 'Biologiya', 1540),
  _Subject('ona_tili', 'Ona tili', 824),
  _Subject('huquq', 'Huquq', 644),
  _Subject('jahon_tarixi', 'Jahon tarixi', 620),
];

/// Tahlil ekrani uchun aralash ro'yxat (fanlararo "zaif/kuchli mavzular").
const _topicNames = <String>[
  'Tabiiy geografiya',
  'Aholi va iqtisodiyot',
  'Qadimgi davr',
  'O\'rta asrlar',
  'Algebra asoslari',
  'Geometriya',
  'Hujayra biologiyasi',
  'Inson anatomiyasi',
];

/// Fan bo'yicha bo'limlar — nomlar REAL bankdagi eng katta `topic` larning
/// o'qiladigan ko'rinishi (`natural_va_butun_sonlar` -> "Natural va butun
/// sonlar"). Bankda bo'limlar ancha ko'p (matematika 196, geografiya 180),
/// lekin demo ro'yxati qisqa: `topic_count` shu ro'yxat uzunligidan olinadi,
/// ya'ni kartochkadagi son bilan tanlagichdagi ro'yxat HAR DOIM mos keladi.
const _topicsBySubject = <String, List<String>>{
  'geografiya': [
    'Atlas bilan ishlash',
    'Yevrosiyo',
    'Geografik masalalar',
    'Yer tabiati',
    'Geografik qobiq',
    'Osiyo subregionlari',
    'Afrika',
    'Atmosfera',
  ],
  'matematika': [
    'Natural va butun sonlar',
    'Algebraik kasrlar',
    "O'nli kasrlar",
    'Kvadratlar ayirmasi',
    'Daraja va xossalari',
    "Yig'indi va ayirma kvadrati",
    'Logarifmik tenglamalar',
    'Chiziqli tenglama',
  ],
  'ozbekiston_tarixi': [
    'Iqtisodiy islohotlar',
    "Qadimgi Sharq va O'rta Osiyo",
    'Qadimgi Yunoniston',
    'Tashqi siyosat',
    "Mustaqillik e'lon qilinishi",
    'Fuqarolik jamiyati',
    "Ma'naviy va madaniy taraqqiyot",
    'Ilm-fan va sport',
  ],
  'biologiya': [
    'Energiya almashinuvi',
    'Nuklein kislotalar',
    "Suvo'tlar",
    "Zamburug'lar va lishayniklar",
    'Oqsillar',
    "Urug', transpiratsiya, fotosintez",
    'Viruslar va bakteriyalar',
    'Prokariot hujayra',
  ],
  'ona_tili': [
    "Qo'shimchalar uslubiyati",
    "So'z qo'llash me'yorlari",
    "Fe'l so'z turkumi",
    "So'z turkumlari",
    'Morfemika',
    'Imlo savodxonligi',
    'Leksik birliklar',
    "Gap bo'laklari",
  ],
  'huquq': [
    'Huquq nazariyasi',
    'Huquqbuzarlik va javobgarlik',
    'Davlat va jamiyat',
    'Tarixiy xronologiya',
    'DTM amaliyoti',
    'Voyaga yetmaganlar huquqlari',
    'Davlat boshqaruvi',
    'Konstitutsiya',
  ],
  'jahon_tarixi': [
    '1991–2017: dunyo mamlakatlari',
    "Eron, Pokiston, Afg'oniston",
    'Hindiston va Turkiya',
    'Lotin Amerikasi va Afrika',
    'Globallashuv',
    'Suriya, Iroq, Isroil',
    'Yaponiya',
    'Xitoy Xalq Respublikasi',
  ],
};

List<String> _topicsOf(String subjectCode) =>
    _topicsBySubject[subjectCode] ?? _topicNames;

const _regions = <Map<String, dynamic>>[
  {'code': 'TOSHKENT_SHAHRI', 'uz': 'Toshkent shahri', 'ru': 'город Ташкент'},
  {'code': 'TOSHKENT', 'uz': 'Toshkent viloyati', 'ru': 'Ташкентская область'},
  {'code': 'ANDIJON', 'uz': 'Andijon', 'ru': 'Андижан'},
  {'code': 'BUXORO', 'uz': 'Buxoro', 'ru': 'Бухара'},
  {'code': 'FARGONA', 'uz': "Farg'ona", 'ru': 'Фергана'},
  {'code': 'JIZZAX', 'uz': 'Jizzax', 'ru': 'Джизак'},
  {'code': 'XORAZM', 'uz': 'Xorazm', 'ru': 'Хорезм'},
  {'code': 'NAMANGAN', 'uz': 'Namangan', 'ru': 'Наманган'},
  {'code': 'NAVOIY', 'uz': 'Navoiy', 'ru': 'Навои'},
  {'code': 'QASHQADARYO', 'uz': 'Qashqadaryo', 'ru': 'Кашкадарья'},
  {'code': 'QORAQALPOGISTON', 'uz': "Qoraqalpog'iston", 'ru': 'Каракалпакстан'},
  {'code': 'SAMARQAND', 'uz': 'Samarqand', 'ru': 'Самарканд'},
  {'code': 'SIRDARYO', 'uz': 'Sirdaryo', 'ru': 'Сырдарья'},
  {'code': 'SURXONDARYO', 'uz': 'Surxondaryo', 'ru': 'Сурхандарья'},
];

final _announcements = <Map<String, dynamic>>[
  {
    'id': 'ann-1',
    'title': "Topag'on beta ishga tushdi",
    'body': "13 430 ta savol, 7 ta fan. Bellashuvda do'stingizni yenging va "
        "tanga yuting. Fikr-mulohazangizni Sozlamalar → Yordam orqali yuboring.",
    'kind': 'news',
    'published_at': '2026-08-01T09:00:00Z',
  },
  {
    'id': 'ann-2',
    'title': 'Yangi: shaxsiy eslatmalar',
    'body': 'Har qanday savolga eslatma yozib qo\'yishingiz mumkin — '
        'takrorlashda juda qo\'l keladi.',
    'kind': 'update',
    'published_at': '2026-07-28T12:00:00Z',
  },
];

final _children = <Map<String, dynamic>>[
  {
    'student_id': 'mock-student-1',
    'display_name': 'Diyorbek',
    'grade': 9,
    'region_code': 'TOSHKENT_SHAHRI',
    'progress': {
      'xp': 1840,
      'level': 19,
      'streak_days': 6,
      'answered': 214,
      'correct': 168,
      'accuracy': 0.785,
    },
  },
  {
    'student_id': 'mock-student-2',
    'display_name': 'Malika',
    'grade': 6,
    'region_code': 'TOSHKENT_SHAHRI',
    'progress': {
      'xp': 720,
      'level': 8,
      'streak_days': 2,
      'answered': 96,
      'correct': 61,
      'accuracy': 0.635,
    },
  },
];

/// Demo savol banki. Haqiqiy savollar — jyuri oldida "lorem ipsum" chiqmasin.
const _bank = <String, List<_Q>>{
  'geografiya': [
    _Q('geo-m1', "O'zbekistonning eng baland cho'qqisi qaysi?",
        ['Adelunga', 'Hazrat Sulton', 'Beshtor', 'Chimyon'], 'b',
        'Hazrat Sulton (4643 m) — Hisor tizmasida, Surxondaryo viloyatida.'),
    _Q('geo-m2', 'Orol dengizi asosan qaysi ikki daryodan suv olgan?',
        ['Zarafshon va Chirchiq', 'Amudaryo va Sirdaryo', 'Sirdaryo va Norin', 'Amudaryo va Qashqadaryo'], 'b',
        "Amudaryo va Sirdaryo suvining sug'orishga olinishi Orol qurishining asosiy sababi."),
    _Q('geo-m3', "O'zbekiston nechta davlat bilan chegaradosh?",
        ['3', '4', '5', '6'], 'c',
        "Qozog'iston, Qirg'iziston, Tojikiston, Afg'oniston va Turkmaniston."),
    _Q('geo-m4', "Qizilqum cho'li qaysi ikki daryo oralig'ida joylashgan?",
        ['Amudaryo va Sirdaryo', 'Zarafshon va Amudaryo', 'Sirdaryo va Chirchiq', 'Norin va Qoradaryo'], 'a',
        "Qizilqum — Amudaryo va Sirdaryo oralig'idagi eng yirik cho'l."),
    _Q('geo-m5', "O'zbekistondagi eng katta sun'iy ko'l qaysi?",
        ['Sariqamish', 'Aydarko\'l', 'Tuzkon', 'Dengizko\'l'], 'b',
        "Aydarko'l 1969-yilgi toshqindan keyin Chordara suv omboridan chiqqan suv hisobiga hosil bo'lgan."),
    _Q('geo-m6', "O'zbekiston hududining taxminan necha foizi tekislik?",
        ['20%', '40%', '60%', '80%'], 'd',
        "Hududning ~4/5 qismi tekislik (Turon pasttekisligi), qolgani tog'lar."),
  ],
  'ozbekiston_tarixi': [
    _Q('hist-m1', 'Amir Temur davlatining poytaxti qaysi shahar edi?',
        ['Buxoro', 'Samarqand', 'Shahrisabz', 'Termiz'], 'b',
        "Amir Temur 1370-yilda Samarqandni poytaxt qilib e'lon qilgan."),
    _Q('hist-m2', "O'zbekiston mustaqilligi qachon e'lon qilingan?",
        ['1990-yil 20-iyun', '1991-yil 31-avgust', '1991-yil 1-sentabr', '1992-yil 8-dekabr'], 'b',
        "31-avgust — e'lon qilingan sana; 1-sentabr Mustaqillik kuni sifatida nishonlanadi."),
    _Q('hist-m3', "Mirzo Ulug'bek rasadxonasi qaysi shaharda qurilgan?",
        ['Buxoro', 'Xiva', 'Samarqand', 'Toshkent'], 'c',
        "1428–1429-yillarda Samarqandda qurilgan; «Ziji jadidi Ko'ragoniy» shu yerda tuzilgan."),
    _Q('hist-m4', 'Jaloliddin Manguberdi qaysi davlat hukmdori edi?',
        ['Somoniylar', 'Xorazmshohlar', 'Qoraxoniylar', 'Temuriylar'], 'b',
        "Xorazmshohlar davlatining so'nggi hukmdori, mo'g'ullarga qarshi kurashgan."),
    _Q('hist-m5', "«Boburnoma» asari muallifi kim?",
        ['Alisher Navoiy', 'Zahiriddin Muhammad Bobur', 'Abu Rayhon Beruniy', 'Mahmud Qoshg\'ariy'], 'b',
        "Bobur o'z xotiralarini turkiy tilda yozgan; asar jahon memuar adabiyotining namunasi."),
    _Q('hist-m6', "O'zbekiston Respublikasi Konstitutsiyasi qachon qabul qilingan?",
        ['1991-yil 31-avgust', '1992-yil 8-dekabr', '1993-yil 1-yanvar', '1994-yil 8-dekabr'], 'b',
        "1992-yil 8-dekabr — Konstitutsiya kuni."),
  ],
  'matematika': [
    _Q('math-m1', '12 va 18 sonlarining eng katta umumiy bo\'luvchisi (EKUB) nechaga teng?',
        ['2', '3', '6', '9'], 'c',
        '12 = 2²·3, 18 = 2·3². Umumiy ko\'paytuvchilar: 2·3 = 6.'),
    _Q('math-m2', 'x + 7 = 15 tenglamada x nechaga teng?',
        ['6', '7', '8', '22'], 'c',
        'Ikkala tomondan 7 ni ayiramiz: x = 15 − 7 = 8.'),
    _Q('math-m3', "Radiusi 5 sm bo'lgan doiraning yuzi (π ≈ 3,14):",
        ['31,4 sm²', '78,5 sm²', '157 sm²', '25 sm²'], 'b',
        'S = πr² = 3,14 · 25 = 78,5 sm².'),
    _Q('math-m4', "To'g'ri burchakli uchburchakda katetlar 3 va 4 bo'lsa, gipotenuza nechaga teng?",
        ['5', '6', '7', '12'], 'a',
        'Pifagor teoremasi: c² = 3² + 4² = 25, c = 5.'),
    _Q('math-m5', '2¹⁰ nechaga teng?',
        ['512', '1000', '1024', '2048'], 'c',
        '2¹⁰ = 1024. Informatikada 1 KB = 1024 bayt shundan.'),
    _Q('math-m6', "Agar a = −3 bo'lsa, a² − 2a qiymati nechaga teng?",
        ['3', '9', '15', '−15'], 'c',
        '(−3)² − 2·(−3) = 9 + 6 = 15.'),
  ],
  'biologiya': [
    _Q('bio-m1', "Fotosintez o'simlik hujayrasining qaysi organoidida boradi?",
        ['Mitoxondriya', 'Xloroplast', 'Ribosoma', 'Yadro'], 'b',
        'Xloroplastdagi xlorofill yorug\'lik energiyasini yutadi.'),
    _Q('bio-m2', 'Inson qonining qaysi tarkibiy qismi kislorod tashiydi?',
        ['Leykotsit', 'Trombotsit', 'Eritrotsit', 'Plazma'], 'c',
        'Eritrotsitlardagi gemoglobin kislorodni bog\'lab tashiydi.'),
    _Q('bio-m3', 'DNK molekulasining qo\'sh spiral tuzilishini kimlar kashf etgan?',
        ['Mendel va Morgan', 'Uotson va Krik', 'Paster va Kox', 'Darvin va Uolles'], 'b',
        'Jeyms Uotson va Frensis Krik, 1953-yil.'),
    _Q('bio-m4', 'Inson tanasi hujayrasida nechta xromosoma juftligi bor?',
        ['21', '22', '23', '46'], 'c',
        '23 juft = 46 ta xromosoma; shundan 1 juft jinsiy xromosoma.'),
    _Q('bio-m5', 'Bakteriyalar qaysi hujayra turiga kiradi?',
        ['Prokariot', 'Eukariot', 'Virus', 'Zamburug\''], 'a',
        'Prokariotlarda shakllangan yadro qobig\'i bo\'lmaydi.'),
    _Q('bio-m6', 'Odam organizmida oqsil sintezi qaysi organoidda amalga oshadi?',
        ['Lizosoma', 'Ribosoma', 'Golji apparati', 'Vakuola'], 'b',
        'Ribosoma — mRNK dagi kodni aminokislotalar zanjiriga aylantiradi.'),
  ],
  'ona_tili': [
    _Q('uz-m1', "«Kitob» so'zi qaysi so'z turkumiga mansub?",
        ['Ot', 'Sifat', 'Fe\'l', 'Ravish'], 'a',
        'Ot — predmetni bildiradi va «kim? nima?» so\'roqlariga javob beradi.'),
    _Q('uz-m2', "O'zbek adabiy tilida nechta unli tovush bor?",
        ['5', '6', '8', '10'], 'b',
        'a, o, i, u, e, o‘ — jami 6 ta unli.'),
    _Q('uz-m3', "«Yozmoq» fe'lining o'zagi qaysi?",
        ['yoz', 'yozm', 'moq', 'zmoq'], 'a',
        '-moq — noaniq shakl qo\'shimchasi; o\'zak «yoz».'),
    _Q('uz-m4', "«Baxt» so'zining ma'nodoshi (sinonimi) qaysi?",
        ['Qayg\'u', 'Saodat', 'Mehnat', 'Sabr'], 'b',
        'Saodat — baxt bilan bir xil ma\'noni bildiradi.'),
    _Q('uz-m5', "Qo'shma gapda sodda gaplar nima orqali bog'lanadi?",
        ['Faqat intonatsiya', 'Faqat bog\'lovchi', 'Bog\'lovchi va intonatsiya', 'Qo\'shimcha'], 'c',
        'Bog\'langan va ergashgan qo\'shma gaplarda ikkalasi ham ishlaydi.'),
  ],
  'huquq': [
    _Q('law-m1', "O'zbekiston Respublikasi Oliy Majlisi nechta palatadan iborat?",
        ['1', '2', '3', '4'], 'b',
        'Qonunchilik palatasi va Senat.'),
    _Q('law-m2', "O'zbekistonda voyaga yetish yoshi necha?",
        ['16', '17', '18', '21'], 'c',
        '18 yoshdan fuqaro to\'liq muomala layoqatiga ega bo\'ladi.'),
    _Q('law-m3', 'Konstitutsiyaga ko\'ra davlat tili qaysi?',
        ['Rus tili', 'O\'zbek tili', 'Ingliz tili', 'Qoraqalpoq tili'], 'b',
        'Konstitutsiyaning 4-moddasi.'),
    _Q('law-m4', 'Sud hokimiyati qaysi hokimiyat tarmog\'iga kiradi?',
        ['Qonun chiqaruvchi', 'Ijro etuvchi', 'Sud', 'Nazorat'], 'c',
        'Hokimiyat uch tarmoqqa bo\'linadi: qonun chiqaruvchi, ijro etuvchi, sud.'),
  ],
  'jahon_tarixi': [
    _Q('wh-m1', 'Birinchi jahon urushi qaysi yillarda bo\'lgan?',
        ['1905–1907', '1914–1918', '1939–1945', '1918–1922'], 'b',
        'Urush 1914-yil iyulda boshlanib, 1918-yil 11-noyabrda tugagan.'),
    _Q('wh-m2', 'Buyuk Fransuz inqilobi qaysi yilda boshlangan?',
        ['1776', '1789', '1804', '1848'], 'b',
        '1789-yil 14-iyul — Bastiliya qamalining olinishi.'),
    _Q('wh-m3', 'Rim imperiyasi qachon G\'arbiy va Sharqiy qismga bo\'lingan?',
        ['313-yil', '395-yil', '476-yil', '1453-yil'], 'b',
        'Feodosiy I vafotidan keyin, 395-yilda.'),
    _Q('wh-m4', 'Amerikaga 1492-yilda kim yetib borgan?',
        ['Vasko da Gama', 'Xristofor Kolumb', 'Ferdinand Magellan', 'Amerigo Vespuchchi'], 'b',
        'Kolumb Bahama orollariga yetib borgan, o\'zini Hindistonda deb o\'ylagan.'),
  ],
};
