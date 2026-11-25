import '../core/typing_session.dart';
import '../models/post.dart';
import '../models/profile.dart';
import '../models/publish_outcome.dart';

/// Everything the app asks of the server. [HttpBackend] talks to the AWS API;
/// [DemoBackend] keeps sample data in memory for development and tests.
abstract class Backend {
  /// The signed-in user's id.
  String get myId;

  /// The signed-in user's profile, or null before it has been created.
  Future<Profile?> me();

  /// Throws [ApiException] with code `handle_taken` when the handle is in use.
  Future<Profile> saveProfile({
    required String handle,
    required String displayName,
    String bio = '',
    required String locale,
    required String timeZone,
  });

  Future<Profile> user(String id);

  Future<FeedPage> feed({required String lang, bool following = false, String? authorId, String? before});

  Future<({bool empathized, int count})> toggleEmpathy(String postId);

  Future<PublishOutcome> publish({required String text, required TypingSession session, required String localDate});

  /// The session must record the change from the post's current text.
  Future<PublishOutcome> edit(
    String postId, {
    required String text,
    required TypingSession session,
    required String localDate,
  });

  Future<void> delete(String postId);

  /// Throws [ApiException] with code `not_allowed` unless both people have follow permission.
  Future<void> follow(String userId);
  Future<void> unfollow(String userId);
}

class FeedPage {
  const FeedPage(this.items, this.next);
  final List<Post> items;

  /// Cursor for the next page, or null at the end.
  final String? next;
}

class ApiException implements Exception {
  const ApiException(this.status, this.code);
  final int status;
  final String code;

  @override
  String toString() => 'ApiException($status, $code)';
}

/// The writer's calendar day, which is what counts toward writing days.
String localDateOf(DateTime now) =>
    '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
