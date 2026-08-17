import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/token_store.dart';
import 'mock_backend.dart';


const _apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL');


final apiBaseUrl = _resolveApiBaseUrl();

String _resolveApiBaseUrl() {
  if (_apiBaseUrlOverride.isNotEmpty) return _apiBaseUrlOverride;
  
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

const imageBaseUrl = String.fromEnvironment('IMAGE_BASE_URL',
    defaultValue: 'https://cdn.topagon.uz');

const _guestUserId = '00000000-0000-0000-0000-000000000001';


final localeCodeProvider = StateProvider<String>((_) => 'uz-Latn');


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
  if (kMockMode) dio.interceptors.add(MockInterceptor());
  return dio;
});


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


String? resolveImage(String? key) => key == null ? null : '$imageBaseUrl/$key';
