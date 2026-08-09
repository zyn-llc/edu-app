import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/prefs.dart';

/// In-memory + persisted holder for the JWT pair. The Dio interceptor reads
/// [accessToken] on every request; the auth controller updates it on login,
/// refresh, and logout.
///
/// NOTE (security): on web this persists to localStorage, which is readable by
/// any script running on the page — the standard XSS tradeoff for SPAs. Acceptable
/// for the MVP; revisit (httpOnly cookie flow) before handling payments.
class TokenStore {
  final SharedPreferences _prefs;
  String? _access;
  String? _refresh;

  TokenStore(this._prefs) {
    _access = _prefs.getString(PrefKeys.accessToken);
    _refresh = _prefs.getString(PrefKeys.refreshToken);
  }

  String? get accessToken => _access;
  String? get refreshToken => _refresh;
  bool get hasTokens => _access != null && _refresh != null;

  Future<void> save(String access, String refresh) async {
    _access = access;
    _refresh = refresh;
    await _prefs.setString(PrefKeys.accessToken, access);
    await _prefs.setString(PrefKeys.refreshToken, refresh);
  }

  /// Replace just the access token (after a refresh that didn't rotate refresh).
  Future<void> setAccess(String access) async {
    _access = access;
    await _prefs.setString(PrefKeys.accessToken, access);
  }

  Future<void> clear() async {
    _access = null;
    _refresh = null;
    await _prefs.remove(PrefKeys.accessToken);
    await _prefs.remove(PrefKeys.refreshToken);
  }
}

final tokenStoreProvider = Provider<TokenStore>(
  (ref) => TokenStore(ref.read(sharedPreferencesProvider)),
);
