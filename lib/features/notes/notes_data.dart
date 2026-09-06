import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../auth/auth_controller.dart';

/// One note. `questionId`/`subjectId` are set when the note was written from a
/// quiz result, so we can later show "your note on this question".
class Note {
  final String id;
  final String? title;
  final String body;
  final String? questionId;
  final String? subjectId;
  final DateTime updatedAt;

  Note({
    required this.id,
    required this.title,
    required this.body,
    required this.questionId,
    required this.subjectId,
    required this.updatedAt,
  });

  factory Note.fromJson(Map<String, dynamic> j) => Note(
        id: j['id'] as String,
        title: j['title'] as String?,
        body: j['body'] as String,
        questionId: j['question_id'] as String?,
        subjectId: j['subject_id'] as String?,
        updatedAt:
            DateTime.tryParse(j['updated_at'] as String? ?? '')?.toLocal() ??
                DateTime.now(),
      );
}

class NotesRepository {
  final Ref ref;
  NotesRepository(this.ref);

  Future<List<Note>> list({String? questionId, String? subjectId}) async {
    final params = <String, dynamic>{'limit': 100};
    if (questionId != null) params['question_id'] = questionId;
    if (subjectId != null) params['subject_id'] = subjectId;
    final res =
        await ref.read(dioProvider).get('/v1/notes', queryParameters: params);
    final items = (res.data as Map<String, dynamic>)['items'] as List;
    return [for (final e in items) Note.fromJson(e as Map<String, dynamic>)];
  }

  Future<Note> create({
    required String body,
    String? title,
    String? questionId,
    String? subjectId,
  }) async {
    final res = await ref.read(dioProvider).post('/v1/notes', data: {
      'body': body,
      if (title != null && title.isNotEmpty) 'title': title,
      if (questionId != null) 'question_id': questionId,
      if (subjectId != null) 'subject_id': subjectId,
    });
    return Note.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Note> update(String id, {String? body, String? title}) async {
    final res = await ref.read(dioProvider).patch('/v1/notes/$id', data: {
      if (body != null) 'body': body,
      if (title != null) 'title': title,
    });
    return Note.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> delete(String id) async {
    await ref.read(dioProvider).delete('/v1/notes/$id');
  }
}

final notesRepositoryProvider =
    Provider<NotesRepository>((ref) => NotesRepository(ref));

/// All of the signed-in user's notes. Re-fetches on login/logout: notes are
/// per-account, so a logged-out cache would be someone else's data.
final notesProvider = FutureProvider<List<Note>>((ref) async {
  ref.watch(authControllerProvider);
  return ref.read(notesRepositoryProvider).list();
});

/// Notes attached to one question — used by the result screen.
final questionNotesProvider =
    FutureProvider.family<List<Note>, String>((ref, questionId) async {
  ref.watch(authControllerProvider);
  return ref.read(notesRepositoryProvider).list(questionId: questionId);
});