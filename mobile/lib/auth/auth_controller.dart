import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import 'auth_models.dart';
import 'token_store.dart';

/// Result of requesting an OTP. In dev the backend returns the code so we can
/// surface it for testing; in prod [debugCode] is null and the code arrives by SMS.
class OtpRequest {
  final int retryAfterSeconds;
  final int expiresInSeconds;
  final String? debugCode;
  OtpRequest(this.retryAfterSeconds, this.expiresInSeconds, this.debugCode);

  factory OtpRequest.fromJson(Map<String, dynamic> j) => OtpRequest(
        (j['retry_after_seconds'] as num?)?.toInt() ?? 60,
        (j['expires_in_seconds'] as num?)?.toInt() ?? 300,
        j['debug_code'] as String?,
      );
}

class TelegramLogin {
  final String nonce;
  final String deepLink;
  final int expiresInSeconds;

  final String confirmCode;

  TelegramLogin(this.nonce, this.deepLink, this.expiresInSeconds,
      this.confirmCode);

  factory TelegramLogin.fromJson(Map<String, dynamic> j) => TelegramLogin(
        j['nonce'] as String,
        j['deep_link'] as String,
        (j['expires_in_seconds'] as num?)?.toInt() ?? 600,
        (j['confirm_code'] as String?) ?? '',
      );
}

class AuthMethods {
  final bool password;
  final bool phone;
  final bool telegram;
  final bool invite;
  final String? telegramBotUsername;

  final bool passwordRegisterRequiresInvite;

  const AuthMethods({
    this.password = true,
    this.phone = true,
    this.telegram = true,
    this.invite = true,
    this.telegramBotUsername,
    this.passwordRegisterRequiresInvite = true,
  });

  factory AuthMethods.fromJson(Map<String, dynamic> j) => AuthMethods(
        password: j['password'] as bool? ?? false,
        phone: j['phone'] as bool? ?? true,
        telegram: j['telegram'] as bool? ?? true,
        invite: j['invite'] as bool? ?? true,
        telegramBotUsername: j['telegram_bot_username'] as String?,
        passwordRegisterRequiresInvite:
            j['password_register_requires_invite'] as bool? ?? true,
      );

  bool get any => password || phone || telegram || invite;
}

class AuthRepository {
  final Ref ref;
  AuthRepository(this.ref);

  Future<AuthMethods> methods() async {
    final res = await _raw.get('/v1/auth/methods');
    return AuthMethods.fromJson(res.data as Map<String, dynamic>);
  }

  // Auth endpoints use the bare Dio (no Bearer/refresh interceptor).
  Dio get _raw => ref.read(rawDioProvider);
  // /me uses the authenticated Dio so the Bearer attaches automatically.
  Dio get _authed => ref.read(dioProvider);

  Future<OtpRequest> requestOtp(String phone, {String role = 'student'}) async {
    final res = await _raw.post('/v1/auth/otp/request',
        data: {'phone': phone, 'role': role});
    return OtpRequest.fromJson(res.data as Map<String, dynamic>);
  }

  Future<TokenPair> verifyOtp(
    String phone,
    String code, {
    String? displayName,
    String? regionCode,
    int? grade,
  }) async {
    final res = await _raw.post('/v1/auth/otp/verify', data: {
      'phone': phone,
      'code': code,
      if (displayName != null) 'display_name': displayName,
      if (regionCode != null) 'region_code': regionCode,
      if (grade != null) 'grade': grade,
    });
    return TokenPair.fromJson(res.data as Map<String, dynamic>);
  }

  /// yozsa so'rov behuda ketmasin.
  Future<TokenPair> redeemInvite(
    String code, {
    String? displayName,
    int? grade,
    String? referredBy,
  }) async {
    final clean = code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final res = await _raw.post('/v1/auth/invite', data: {
      'code': clean,
      if (displayName != null && displayName.isNotEmpty)
        'display_name': displayName,
      if (grade != null) 'grade': grade,
      if (referredBy != null && referredBy.isNotEmpty)
        'referred_by': referredBy,
    });
    return TokenPair.fromJson(res.data as Map<String, dynamic>);
  }

  ///
  /// jadvaldan (`invite_codes`) sarflaydi — botlarga qarshi yagona
  Future<TokenPair> register(
    String username,
    String password, {
    String? displayName,
    int? grade,
    String? inviteCode,
    String? joinCode,
    String? referredBy,
  }) async {
    final res = await _raw.post('/v1/auth/register', data: {
      'username': username.trim(),
      'password': password,
      if (displayName != null && displayName.trim().isNotEmpty)
        'display_name': displayName.trim(),
      if (grade != null) 'grade': grade,
      if (inviteCode != null && inviteCode.trim().isNotEmpty)
        'invite_code': inviteCode.trim(),
      if (joinCode != null && joinCode.trim().isNotEmpty)
        'join_code': joinCode.trim(),
      if (referredBy != null && referredBy.isNotEmpty)
        'referred_by': referredBy,
    });
    return TokenPair.fromJson(res.data as Map<String, dynamic>);
  }

  Future<TokenPair> login(String username, String password) async {
    final res = await _raw.post('/v1/auth/login',
        data: {'username': username.trim(), 'password': password});
    return TokenPair.fromJson(res.data as Map<String, dynamic>);
  }

  Future<bool?> usernameFree(String username) async {
    try {
      final res = await _raw.get('/v1/auth/username-free',
          queryParameters: {'username': username.trim()});
      return (res.data as Map<String, dynamic>)['free'] as bool?;
    } catch (_) {
      return null;
    }
  }

  Future<TokenPair?> setPassword(String password, {String? username}) async {
    final res = await _authed.post('/v1/auth/password', data: {
      'password': password,
      if (username != null && username.trim().isNotEmpty)
        'username': username.trim(),
    });
    final data = res.data as Map<String, dynamic>;
    if (data['access_token'] == null || data['refresh_token'] == null) {
      return null;
    }
    return TokenPair.fromJson(data);
  }

  /// Telegram kirishini boshlaydi: nonce + botga havola.
  Future<TelegramLogin> telegramStart() async {
    final res = await _raw.post('/v1/auth/telegram/start');
    return TelegramLogin.fromJson(res.data as Map<String, dynamic>);
  }

  /// Havola muddati tugasa DioException (410) ko'tariladi.
  Future<TokenPair?> telegramPoll(String nonce) async {
    final res =
        await _raw.post('/v1/auth/telegram/poll', data: {'nonce': nonce});
    final data = res.data as Map<String, dynamic>;
    if (data['status'] != 'ok') return null;
    return TokenPair.fromJson(data);
  }

  Future<MeOverview> me() async {
    final res = await _authed.get('/v1/me');
    return MeOverview.fromJson(res.data as Map<String, dynamic>);
  }

  Future<UserMe> updateProfile({
    String? displayName,
    String? regionCode,
    int? grade,
    int? avatarColor,
    bool? tgNotifications,
  }) async {
    final res = await _authed.patch('/v1/auth/me', data: {
      if (displayName != null) 'display_name': displayName,
      if (regionCode != null) 'region_code': regionCode,
      if (grade != null) 'grade': grade,
      if (avatarColor != null) 'avatar_color': avatarColor,
      if (tgNotifications != null) 'tg_notifications': tgNotifications,
    });
    return UserMe.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<Region>> regions() async {
    final res = await _raw.get('/v1/regions');
    return [
      for (final r in (res.data['regions'] as List))
        Region.fromJson(r as Map<String, dynamic>)
    ];
  }

  Future<Analysis> analysis() async {
    final res = await _authed.get('/v1/me/analysis');
    return Analysis.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> logout(String refreshToken) async {
    try {
      await _raw.post('/v1/auth/logout', data: {'refresh_token': refreshToken});
    } catch (_) {
      // best-effort; local tokens are cleared regardless
    }
  }
}

final authRepositoryProvider =
    Provider<AuthRepository>((ref) => AuthRepository(ref));

// --------------------------------------------------------------------------- //
//  Auth state                                                                 //
// --------------------------------------------------------------------------- //
class AuthState {
  final bool initializing; // first-load /me check in flight
  final UserMe? user;
  const AuthState({this.initializing = false, this.user});

  bool get isAuthenticated => user != null;

  AuthState copyWith({bool? initializing, UserMe? user, bool clearUser = false}) =>
      AuthState(
        initializing: initializing ?? this.initializing,
        user: clearUser ? null : (user ?? this.user),
      );
}

class AuthController extends StateNotifier<AuthState> {
  final Ref ref;
  AuthController(this.ref) : super(const AuthState()) {
    _restore();
  }

  TokenStore get _tokens => ref.read(tokenStoreProvider);
  AuthRepository get _repo => ref.read(authRepositoryProvider);

  /// On launch: if we have stored tokens, confirm the session by fetching /me.
  Future<void> _restore() async {
    if (!_tokens.hasTokens) return;
    state = state.copyWith(initializing: true);
    try {
      final me = await _repo.me();
      state = AuthState(user: me.user);
    } catch (_) {
      await _tokens.clear();
      state = const AuthState();
    }
  }

  /// Completes a login after a verified OTP returned a token pair.
  Future<void> completeLogin(TokenPair pair) async {
    await _tokens.save(pair.accessToken, pair.refreshToken);
    try {
      final me = await _repo.me();
      state = AuthState(user: me.user);
    } catch (_) {
      // tokens are valid but /me failed (e.g. transient) — keep tokens, retry later
      state = const AuthState();
    }
  }

  Future<void> refreshMe() async {
    if (!_tokens.hasTokens) return;
    try {
      final me = await _repo.me();
      state = AuthState(user: me.user);
    } catch (_) {
      // 401 here means the interceptor already cleared tokens
      if (!_tokens.hasTokens) state = const AuthState();
    }
  }

  Future<void> logout() async {
    final rt = _tokens.refreshToken;
    if (rt != null) await _repo.logout(rt);
    await _tokens.clear();
    state = const AuthState();
  }

  /// Save profile edits, then refresh the cached user so the UI updates.
  ///
  /// token boshqa tabda allaqachon aylantirilgan — u BIR MARTALIK), Dio
  /// qayta uloqtiramiz.
  Future<void> updateProfile({
    String? displayName,
    String? regionCode,
    int? grade,
    int? avatarColor,
    bool? tgNotifications,
  }) async {
    try {
      final updated = await _repo.updateProfile(
          displayName: displayName,
          regionCode: regionCode,
          grade: grade,
          avatarColor: avatarColor,
          tgNotifications: tgNotifications);
      state = AuthState(user: updated);
    } catch (_) {
      if (!_tokens.hasTokens) state = const AuthState();
      rethrow;
    }
  }

  Future<void> updateTelegramNotifications(bool enabled) =>
      updateProfile(tgNotifications: enabled);
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) => AuthController(ref));

final authMethodsProvider = FutureProvider<AuthMethods>((ref) async {
  try {
    return await ref.read(authRepositoryProvider).methods();
  } catch (_) {
    return const AuthMethods();
  }
});

/// Static region reference for the profile picker (cached for the session).
final regionsProvider = FutureProvider<List<Region>>(
    (ref) => ref.read(authRepositoryProvider).regions());

/// Topic-mastery analysis for the logged-in student. Re-fetches on auth change.
final analysisProvider = FutureProvider<Analysis?>((ref) async {
  final auth = ref.watch(authControllerProvider);
  if (!auth.isAuthenticated) return null;
  return ref.read(authRepositoryProvider).analysis();
});

/// Full /me overview (profile + progress + rank) for the dashboard. Re-fetches
/// when auth state changes.
final meOverviewProvider = FutureProvider<MeOverview?>((ref) async {
  final auth = ref.watch(authControllerProvider);
  if (!auth.isAuthenticated) return null;
  return ref.read(authRepositoryProvider).me();
});
