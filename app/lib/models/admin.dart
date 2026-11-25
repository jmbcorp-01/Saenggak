import 'post.dart' show parseServerTime;

class AdminStats {
  const AdminStats({
    required this.users,
    required this.usersToday,
    required this.posts,
    required this.postsToday,
    required this.pendingReview,
    required this.suspended,
  });

  factory AdminStats.fromJson(Map<String, dynamic> j) => AdminStats(
    users: (j['users'] as num).toInt(),
    usersToday: (j['usersToday'] as num).toInt(),
    posts: (j['posts'] as num).toInt(),
    postsToday: (j['postsToday'] as num).toInt(),
    pendingReview: (j['pendingReview'] as num).toInt(),
    suspended: (j['suspended'] as num).toInt(),
  );

  final int users;
  final int usersToday;
  final int posts;
  final int postsToday;
  final int pendingReview;
  final int suspended;
}

/// A blocked post waiting for an admin.
class ReviewItem {
  const ReviewItem({
    required this.id,
    required this.authorHandle,
    required this.authorName,
    required this.body,
    required this.createdAt,
    this.blockedReason,
    this.issues = const [],
  });

  factory ReviewItem.fromJson(Map<String, dynamic> j) => ReviewItem(
    id: j['id'] as String,
    authorHandle: j['authorHandle'] as String,
    authorName: j['authorName'] as String,
    body: j['body'] as String,
    blockedReason: j['blockedReason'] as String?,
    issues: (j['issues'] as List? ?? const []).cast<String>(),
    createdAt: parseServerTime(j['createdAt'] as String),
  );

  final String id;
  final String authorHandle;
  final String authorName;
  final String body;
  final String? blockedReason;
  final List<String> issues;
  final DateTime createdAt;
}

class AdminUser {
  const AdminUser({
    required this.id,
    required this.handle,
    required this.displayName,
    this.bio = '',
    this.photoUrl,
    this.posts = 0,
    this.recentBlocks = 0,
    this.suspended = false,
    this.suspendedReason,
  });

  factory AdminUser.fromJson(Map<String, dynamic> j) => AdminUser(
    id: j['id'] as String,
    handle: j['handle'] as String,
    displayName: j['displayName'] as String,
    bio: j['bio'] as String? ?? '',
    photoUrl: j['photoUrl'] as String?,
    posts: (j['posts'] as num? ?? 0).toInt(),
    recentBlocks: (j['recentBlocks'] as num? ?? 0).toInt(),
    suspended: j['suspendedAt'] != null,
    suspendedReason: j['suspendedReason'] as String?,
  );

  final String id;
  final String handle;
  final String displayName;
  final String bio;
  final String? photoUrl;
  final int posts;
  final int recentBlocks;
  final bool suspended;
  final String? suspendedReason;
}

/// Why the content filter held a post, in words.
String blockedReasonName(String? reason) => switch (reason) {
  'profanity' => '욕설·비하',
  'sexual' => '선정적',
  'crime' => '범죄',
  'spam' => '광고·스팸',
  'not_a_thought' => '생각이 아님',
  'classifier_declined' => '필터가 판단 보류',
  _ => '기타',
};
