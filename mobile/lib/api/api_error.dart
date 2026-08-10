import 'package:dio/dio.dart';

import '../l10n/app_localizations.dart';

/// Turns a raw exception into a short, human, localized message. A connection
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
        // ("Invalid token", "Not authenticated") ingliz tilida va
        if (error.response?.statusCode == 401) return l.errSessionExpired;
        if (error.response?.statusCode == 429) return l.errTooFast;
        final data = error.response?.data;
        if (data is Map && data['title'] is String) return data['title'] as String;
        return l.errServer;
      default:
        return l.errServer;
    }
  }
  return l.errServer;
}
