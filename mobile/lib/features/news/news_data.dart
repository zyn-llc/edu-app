import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';

/// A server-driven announcement. Adding one is a DB insert, not an app release.
class Announcement {
  final String id;
  final String title;
  final String body;
  final String kind; // news | update | maintenance | promo
  final DateTime publishedAt;

  Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.kind,
    required this.publishedAt,
  });

  factory Announcement.fromJson(Map<String, dynamic> j) => Announcement(
        id: j['id'] as String,
        title: j['title'] as String,
        body: j['body'] as String,
        kind: j['kind'] as String? ?? 'news',
        publishedAt:
            DateTime.tryParse(j['published_at'] as String? ?? '')?.toLocal() ??
                DateTime.now(),
      );
}

class NewsRepository {
  final Ref ref;
  NewsRepository(this.ref);

  Future<List<Announcement>> list({int? grade}) async {
    // No auth needed: a maintenance notice is useless if only logged-in users
    // can read it. The backend serves active + already-published rows only.
    final res = await ref.read(dioProvider).get('/v1/announcements',
        queryParameters: {
          'lang': ref.read(localeCodeProvider),
          if (grade != null) 'grade': grade,
        });
    final items = (res.data as Map<String, dynamic>)['items'] as List;
    return [
      for (final e in items) Announcement.fromJson(e as Map<String, dynamic>)
    ];
  }
}

final newsRepositoryProvider =
    Provider<NewsRepository>((ref) => NewsRepository(ref));

/// Re-fetches when the app language changes so the feed matches the UI.
final newsProvider = FutureProvider<List<Announcement>>((ref) async {
  ref.watch(localeCodeProvider);
  return ref.read(newsRepositoryProvider).list();
});