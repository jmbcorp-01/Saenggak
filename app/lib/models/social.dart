import 'post.dart' show parseServerTime;

/// Reasons a reader can give, in the order the report sheet lists them.
const reportReasons = {
  'ai_or_copied': 'AI가 쓰거나 베낀 글 같아요',
  'abuse': '욕설, 비하, 괴롭힘',
  'sexual': '선정적인 내용',
  'spam': '광고나 스팸',
  'self_harm': '자해나 위험한 행동',
  'impersonation': '다른 사람을 사칭해요',
  'other': '기타',
};

class AppNotification {
  const AppNotification({
    required this.kind,
    required this.at,
    required this.actorId,
    required this.actorHandle,
    required this.actorName,
    this.actorPhotoUrl,
    this.postId,
    this.excerpt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
    kind: j['kind'] as String,
    at: parseServerTime(j['at'] as String),
    actorId: j['actorId'] as String,
    actorHandle: j['actorHandle'] as String,
    actorName: j['actorName'] as String,
    actorPhotoUrl: j['actorPhotoUrl'] as String?,
    postId: j['postId'] as String?,
    excerpt: j['excerpt'] as String?,
  );

  /// `empathy`, `follow`, or `post` for a new post by someone whose alerts are on.
  final String kind;
  final DateTime at;
  final String actorId;
  final String actorHandle;
  final String actorName;
  final String? actorPhotoUrl;
  final String? postId;
  final String? excerpt;

  /// [at] as the server's cursor for the next page.
  String get cursor => at.toUtc().toIso8601String();
}

class NotificationsPage {
  const NotificationsPage(this.items, this.unread, this.next);
  final List<AppNotification> items;
  final int unread;
  final String? next;
}

class BlockedUser {
  const BlockedUser({required this.id, required this.handle, required this.displayName});

  factory BlockedUser.fromJson(Map<String, dynamic> j) =>
      BlockedUser(id: j['id'] as String, handle: j['handle'] as String, displayName: j['displayName'] as String);

  final String id;
  final String handle;
  final String displayName;
}
