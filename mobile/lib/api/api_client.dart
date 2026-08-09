import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/token_store.dart';
import 'mock_backend.dart';

/// Backend manzili. Build vaqtida almashtiriladi:
///   web dev:  flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
///   qurilma:  flutter run -d <device> --dart-define=API_BASE_URL=http://<wifi-ip>:8000
///   prod:     flutter build web --release --dart-define=API_BASE_URL=https://api.topagon.uz
const _apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL');

/// Standart qiymat platformaga bog'liq:
///   - Android emulyatori host mashinaga `10.0.2.2` orqali chiqadi;
///   - web esa brauzerda ishlaydi, u yerda `10.0.2.2` mavjud emas — `127.0.0.1`.
///
/// DIQQAT: Windows'da `localhost` IPv6 `::1` ga hal bo'ladi, Docker esa IPv4'da
/// tinglaydi. Shu sababli ataylab `localhost` emas, `127.0.0.1`.
final apiBaseUrl = _resolveApiBaseUrl();

String _resolveApiBaseUrl() {
  if (_apiBaseUrlOverride.isNotEmpty) return _apiBaseUrlOverride;
  // RELEASE build'da standart qiymatga TUSHIB QOLISH — jim halokat.
  // `flutter build web --release` ni `--dart-define=API_BASE_URL` siz
  // ishga tushirish `127.0.0.1:8000` ga qaraydigan bundle beradi: u
  // ishlab chiquvchining mashinasida BEXATO ishlaydi va foydalanuvchida
  // hech qachon ochilmaydi. `deploy.sh` define'ni beradi, lekin qo'lda
  // qilingan build bermaydi — shuning uchun build emas, ishga tushirish
  // paytida yiqilamiz, va sababi aniq aytiladi.
  if (kReleaseMode && !kMockMode) {
    throw StateError(
      'API_BASE_URL berilmagan. Release build shunday chiqarilishi kerak:\n'
      '  flutter build web --release '
      '--dart-define=API_BASE_URL=https://api.topagon.uz '
      '--dart-define=WEB_BASE_URL=https://app.topagon.uz',
    );
  }
  return kIsWeb ? 'http://127.0.0.1:8000' : 'http://10.0.2.2:8000';
}

/// Fan muqovalari va savol rasmlari uchun CDN ildizi.
const imageBaseUrl = String.fromEnvironment('IMAGE_BASE_URL',
    defaultValue: 'https://cdn.topagon.uz');

const _guestUserId = '00000000-0000-0000-0000-000000000001';

/// Language sent to the backend (uz-Latn or ru), kept in sync with the app locale
/// so questions/catalog come back in the right language.
final localeCodeProvider = StateProvider<String>((_) => 'uz-Latn');

/// Bare Dio with NO auth interceptor. Used for the auth endpoints themselves and
/// for the refresh call (so a 401 on refresh can't recurse into another refresh).
final rawDioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: apiBaseUrl,
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 20),
  ));
  dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
    options.headers['Accept-Language'] = ref.read(localeCodeProvider);
    handler.next(options);
  }));
  // Zanjirning OXIRIDA: undan oldingi interceptorlar sarlavhalarni qo'yib
  // bo'lgan bo'ladi, mock esa ularni real server kabi o'qiydi.
  if (kMockMode) dio.interceptors.add(MockInterceptor());
  return dio;
});

/// Authenticated Dio: attaches the Bearer token when logged in, falls back to the
/// guest header otherwise, and transparently refreshes on a 401.
///
/// Refresh is SINGLE-FLIGHT: the backend rotates refresh tokens (one-time use),
/// so if several requests 401ed at the same moment and each fired its own refresh,
/// only the first would win — the rest would present the already-rotated token,
/// fail, and wrongly log the user out. All concurrent 401s share one in-flight
/// refresh Future instead.
Future<bool>? _refreshInFlight;

Future<bool> _refreshTokens(Ref ref) {
  return _refreshInFlight ??= () async {
    try {
      final tokens = ref.read(tokenStoreProvider);
      final raw = ref.read(rawDioProvider);
      final res = await raw.post('/v1/auth/refresh',
          data: {'refresh_token': tokens.refreshToken});
      final data = res.data as Map<String, dynamic>;
      await tokens.save(
          data['access_token'] as String, data['refresh_token'] as String);
      return true;
    } catch (_) {
      // Refresh failed — session is dead. Drop tokens; the caller sees 401 and
      // the UI falls back to logged-out state.
      await ref.read(tokenStoreProvider).clear();
      return false;
    } finally {
      _refreshInFlight = null;
    }
  }();
}

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: apiBaseUrl,
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 20),
  ));

  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      final tokens = ref.read(tokenStoreProvider);
      options.headers['Accept-Language'] = ref.read(localeCodeProvider);
      final access = tokens.accessToken;
      if (access != null) {
        options.headers['Authorization'] = 'Bearer $access';
      } else {
        // Guest practice: lets pre-login answers persist server-side.
        options.headers['X-Debug-User-Id'] = _guestUserId;
      }
      handler.next(options);
    },
    onError: (err, handler) async {
      final tokens = ref.read(tokenStoreProvider);
      final isAuthError = err.response?.statusCode == 401;
      final isRefreshCall = err.requestOptions.path.contains('/v1/auth/refresh');
      final alreadyRetried = err.requestOptions.extra['retried'] == true;

      if (!isAuthError ||
          isRefreshCall ||
          alreadyRetried ||
          tokens.refreshToken == null) {
        return handler.next(err);
      }

      // Try one (shared) refresh, then replay the original request once.
      final ok = await _refreshTokens(ref);
      if (!ok) return handler.next(err);
      try {
        final opts = err.requestOptions;
        opts.extra['retried'] = true;
        opts.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
        final replay = await dio.fetch(opts);
        return handler.resolve(replay);
      } catch (_) {
        return handler.next(err);
      }
    },
  ));
  if (kMockMode) dio.interceptors.add(MockInterceptor());
  return dio;
});

/// Resolves a stored R2 key (e.g. "subjects/geografiya.jpg") to a full URL.
String? resolveImage(String? key) => key == null ? null : '$imageBaseUrl/$key';
