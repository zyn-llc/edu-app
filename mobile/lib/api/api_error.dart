import 'package:dio/dio.dart';

import '../l10n/app_localizations.dart';

/// Turns a raw exception into a short, human, localized message. A connection
/// timeout should read "can't reach the server — check your connection", never
/// a DioException dump on the dashboard.
String humanError(Object error, L10n l) {
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return l.errNoConnection;
      case DioExceptionType.badResponse:
        // 401 — Bearer token butunlay yaroqsiz (yo'q, buzuq, yoki refresh
        // ham muvaffaqiyatsiz bo'lgan). Serverning xom sarlavhasi
        // ("Invalid token", "Not authenticated") ingliz tilida va
        // foydalanuvchiga hech narsa demaydi — sabab tushunarli:
        // sessiya tugagan, qayta kirish kerak.
        if (error.response?.statusCode == 401) return l.errSessionExpired;
        // 429 — cheklovga urildi. Serverning `title` i ("Too many attempts")
        // inglizcha, `detail` esa ba'zan bor, ba'zan yo'q. Bu holat uchun
        // o'zbekcha/ruscha aniq matn bor.
        if (error.response?.statusCode == 429) return l.errTooFast;
        // Server answered — surface its RFC 7807 'title' if present.
        final data = error.response?.data;
        if (data is Map && data['title'] is String) return data['title'] as String;
        return l.errServer;
      default:
        return l.errServer;
    }
  }
  return l.errServer;
}
