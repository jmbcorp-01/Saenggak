import '../l10n/l10n.dart';
import 'post.dart' show parseServerTime;

class AdminStats {
  const AdminStats({
    required this.users,
    required this.usersToday,
    required this.posts,
    required this.postsToday,
    required this.pendingReview,
    required this.suspended,
    this.openReports = 0,
  });

  factory AdminStats.fromJson(Map<String, dynamic> j) => AdminStats(
    users: (j['users'] as num).toInt(),
    usersToday: (j['usersToday'] as num).toInt(),
    posts: (j['posts'] as num).toInt(),
    postsToday: (j['postsToday'] as num).toInt(),
    pendingReview: (j['pendingReview'] as num).toInt(),
    suspended: (j['suspended'] as num).toInt(),
    openReports: (j['openReports'] as num? ?? 0).toInt(),
  );

  final int users;
  final int usersToday;
  final int posts;
  final int postsToday;
  final int pendingReview;
  final int suspended;
  final int openReports;
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
  'profanity' => t('욕설·비하'),
  'sexual' => t('선정적'),
  'crime' => t('범죄'),
  'spam' => t('광고·스팸'),
  'not_a_thought' => t('생각이 아님'),
  'classifier_declined' => t('필터가 판단 보류'),
  _ => t('기타'),
};

class OpenReport {
  const OpenReport({
    required this.id,
    required this.reason,
    required this.userId,
    required this.userHandle,
    required this.userName,
    required this.reporterHandle,
    required this.createdAt,
    this.note = '',
    this.postId,
    this.postBody,
    this.reportsOnUser = 1,
  });

  factory OpenReport.fromJson(Map<String, dynamic> j) => OpenReport(
    id: j['id'] as String,
    reason: j['reason'] as String,
    note: j['note'] as String? ?? '',
    userId: j['userId'] as String,
    userHandle: j['userHandle'] as String,
    userName: j['userName'] as String,
    reporterHandle: j['reporterHandle'] as String,
    postId: j['postId'] as String?,
    postBody: j['postBody'] as String?,
    reportsOnUser: (j['reportsOnUser'] as num? ?? 1).toInt(),
    createdAt: parseServerTime(j['createdAt'] as String),
  );

  final String id;
  final String reason;
  final String note;
  final String userId;
  final String userHandle;
  final String userName;
  final String reporterHandle;
  final String? postId;
  final String? postBody;
  final int reportsOnUser;
  final DateTime createdAt;
}
