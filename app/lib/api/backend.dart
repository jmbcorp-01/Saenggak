import 'dart:typed_data';

import '../core/typing_session.dart';
import '../models/admin.dart';
import '../models/post.dart';
import '../models/profile.dart';
import '../models/publish_outcome.dart';
import '../models/social.dart';

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

  /// Sets the profile photo from a JPEG taken with the camera. Throws
  /// [ApiException] whose code is the reason when the photo is turned down:
  /// `no_face`, `many_faces`, `unclear`, `inappropriate` or `bad_image`.
  Future<Profile> setPhoto(Uint8List jpeg);

  Future<Profile> user(String id);

  /// Ends the session on this device.
  Future<void> signOut();

  /// Erases the account, its posts and photo, and the sign-in. Cannot be undone.
  Future<void> deleteAccount();

  /// Reports a post (its author is reported with it) or, without [postId], a person.
  Future<void> report({String? postId, String? userId, required String reason, String note = ''});
  Future<void> block(String userId);
  Future<void> unblock(String userId);
  Future<List<BlockedUser>> blockedUsers();

  /// 공감 on the reader's posts and new followers, newest first.
  Future<NotificationsPage> notifications({String? before});
  Future<void> markNotificationsSeen();

  Future<List<OpenReport>> openReports();
  Future<void> resolveReport(String reportId, {String note = ''});

  /// Admin pages; the server answers 403 to anyone outside the admins group.
  Future<AdminStats> adminStats();
  Future<List<ReviewItem>> reviewQueue();

  /// [publish] true puts the post in the feed; false keeps it blocked.
  Future<void> reviewPost(String postId, {required bool publish});
  Future<void> removePost(String postId, {String note = ''});
  Future<List<AdminUser>> searchUsers(String query);
  Future<void> setSuspended(String userId, {required bool suspended, String reason = ''});
  Future<void> removePhoto(String userId);

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

  /// One post, for a shared link. Throws [ApiException] 404 when it is gone.
  Future<Post> post(String postId, {required String lang});

  /// Saves the post for later, or takes it off the saved list.
  Future<void> setBookmark(String postId, bool saved);

  /// The reader's saved posts, newest saved first.
  Future<List<Post>> bookmarks({required String lang});

  /// People whose handle or name matches.
  Future<List<PersonHit>> searchPeople(String query);

  /// Posts close in meaning to [query].
  Future<List<Post>> searchPosts(String query, {required String lang});

  /// Everything stored about the reader, as JSON text.
  Future<String> exportData();

  /// A short sentence to type when activity looks automated.
  Future<String> humanCheckPhrase(String lang);

  /// Throws [ApiException] `not_human` when the typing does not pass.
  Future<void> passHumanCheck(String text, TypingSession session);

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

/// A person found by search.
class PersonHit {
  const PersonHit({required this.id, required this.handle, required this.displayName, this.bio = '', this.photoUrl});

  factory PersonHit.fromJson(Map<String, dynamic> j) => PersonHit(
    id: j['id'] as String,
    handle: j['handle'] as String,
    displayName: j['displayName'] as String,
    bio: j['bio'] as String? ?? '',
    photoUrl: j['photoUrl'] as String?,
  );

  final String id;
  final String handle;
  final String displayName;
  final String bio;
  final String? photoUrl;
}

/// The server asks for a typing check (HTTP 428) before more activity.
bool isHumanCheck(Object e) => e is ApiException && e.status == 428;

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
