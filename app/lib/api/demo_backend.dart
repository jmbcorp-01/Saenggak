import 'dart:convert';
import 'dart:typed_data';

import '../core/typing_session.dart';
import '../models/admin.dart';
import '../models/post.dart';
import '../models/profile.dart';
import '../models/publish_outcome.dart';
import '../models/social.dart';
import 'backend.dart';

/// Sample data kept in memory. Used when no server is configured and in tests.
/// The server's content filter and embeddings are not run here: the similar
/// count is a fixed sample and first phrases use a simple word window.
class DemoBackend implements Backend {
  DemoBackend({DateTime Function()? clock, List<Post>? posts, Profile? me})
    : _clock = clock ?? DateTime.now,
      _me = me ?? _sampleMe {
    _posts.addAll(posts ?? _samplePosts(_clock()));
  }

  final DateTime Function() _clock;
  Profile _me;
  final List<Post> _posts = [];
  final Set<String> _claimed = {};
  final Set<String> _days = {};
  final Set<String> _following = {};
  int _next = 0;

  static const _sampleMe = Profile(
    id: 'me',
    handle: 'yoonseo',
    displayName: '윤서',
    bio: '조용한 날에 생각을 씁니다.',
    writingDays: 7,
    isMe: true,
    isAdmin: true,
  );

  @override
  String get myId => _me.id;

  @override
  Future<Profile?> me() async => _me;

  @override
  Future<Profile> saveProfile({
    required String handle,
    required String displayName,
    String bio = '',
    required String locale,
    required String timeZone,
  }) async {
    _me = Profile(
      id: _me.id,
      handle: handle,
      displayName: displayName,
      bio: bio,
      locale: locale,
      timeZone: timeZone,
      writingDays: _me.writingDays,
      followUnlocked: _me.followUnlocked,
      isMe: true,
      isAdmin: _me.isAdmin,
      photoUrl: _me.photoUrl,
    );
    return _me;
  }

  /// No face check here; the photo is kept as a data URL.
  @override
  Future<Profile> setPhoto(Uint8List jpeg) async {
    if (jpeg.length < 3 || jpeg[0] != 0xFF || jpeg[1] != 0xD8 || jpeg[2] != 0xFF) {
      throw const ApiException(400, 'bad_image');
    }
    _me = Profile(
      id: _me.id,
      handle: _me.handle,
      displayName: _me.displayName,
      bio: _me.bio,
      locale: _me.locale,
      timeZone: _me.timeZone,
      writingDays: _me.writingDays,
      followUnlocked: _me.followUnlocked,
      isMe: true,
      isAdmin: _me.isAdmin,
      photoUrl: 'data:image/jpeg;base64,${base64Encode(jpeg)}',
    );
    return _me;
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() async {
    _posts.removeWhere((p) => p.authorId == _me.id);
  }

  // The demo's sample person is an admin, so the admin pages can be tried offline.
  final Set<String> _suspended = {};
  final List<ReviewItem> _queue = [];

  final List<OpenReport> _reports = [];
  final Map<String, BlockedUser> _blocked = {};
  final List<AppNotification> notificationItems = [];
  int _seen = 0;

  @override
  Future<void> report({String? postId, String? userId, required String reason, String note = ''}) async {
    _guard();
    final p = postId == null ? null : _posts.firstWhere((p) => p.id == postId);
    final id = p?.authorId ?? userId!;
    final author = _posts.firstWhere((x) => x.authorId == id, orElse: () => p!);
    _reports.add(
      OpenReport(
        id: '${_reports.length + 1}',
        reason: reason,
        note: note,
        userId: id,
        userHandle: author.authorHandle,
        userName: author.authorName,
        reporterHandle: _me.handle,
        postId: postId,
        postBody: p?.body,
        createdAt: _clock(),
      ),
    );
  }

  @override
  Future<void> block(String userId) async {
    _guard();
    final p = _posts.firstWhere((x) => x.authorId == userId);
    _blocked[userId] = BlockedUser(id: userId, handle: p.authorHandle, displayName: p.authorName);
    _following.remove(userId);
  }

  @override
  Future<void> unblock(String userId) async => _blocked.remove(userId);

  @override
  Future<List<BlockedUser>> blockedUsers() async => _blocked.values.toList();

  @override
  Future<NotificationsPage> notifications({String? before}) async =>
      NotificationsPage(List.of(notificationItems), notificationItems.length - _seen, null);

  @override
  Future<void> markNotificationsSeen() async => _seen = notificationItems.length;

  @override
  Future<List<OpenReport>> openReports() async => List.of(_reports);

  @override
  Future<void> resolveReport(String reportId, {String note = ''}) async =>
      _reports.removeWhere((r) => r.id == reportId);

  @override
  Future<AdminStats> adminStats() async => AdminStats(
    users: {..._posts.map((p) => p.authorId), _me.id}.length,
    usersToday: 1,
    posts: _posts.length,
    postsToday: _posts.where((p) => _clock().difference(p.createdAt).inDays < 1).length,
    pendingReview: _queue.length,
    suspended: _suspended.length,
    openReports: _reports.length,
  );

  @override
  Future<List<ReviewItem>> reviewQueue() async => List.of(_queue);

  /// Adds a held post to the demo's review queue.
  void hold(ReviewItem item) => _queue.add(item);

  @override
  Future<void> reviewPost(String postId, {required bool publish}) async => _queue.removeWhere((q) => q.id == postId);

  @override
  Future<void> removePost(String postId, {String note = ''}) async => _posts.removeWhere((p) => p.id == postId);

  @override
  Future<List<AdminUser>> searchUsers(String query) async {
    final q = query.toLowerCase();
    final seen = <String>{};
    return [
      for (final p in _posts)
        if (seen.add(p.authorId) && (q.isEmpty || p.authorHandle.contains(q) || p.authorName.toLowerCase().contains(q)))
          AdminUser(
            id: p.authorId,
            handle: p.authorHandle,
            displayName: p.authorName,
            posts: _posts.where((x) => x.authorId == p.authorId).length,
            suspended: _suspended.contains(p.authorId),
          ),
    ];
  }

  @override
  Future<void> setSuspended(String userId, {required bool suspended, String reason = ''}) async =>
      suspended ? _suspended.add(userId) : _suspended.remove(userId);

  @override
  Future<void> removePhoto(String userId) async {}

  @override
  Future<Profile> user(String id) async {
    if (id == _me.id) return _me;
    final p = _posts.firstWhere((p) => p.authorId == id, orElse: () => throw const ApiException(404, 'not_found'));
    return Profile(
      id: id,
      handle: p.authorHandle,
      displayName: p.authorName,
      writingDays: 23,
      followUnlocked: true,
      followers: _following.contains(id) ? 1 : 0,
      followedByMe: _following.contains(id),
      blockedByMe: _blocked.containsKey(id),
    );
  }

  @override
  Future<FeedPage> feed({required String lang, bool following = false, String? authorId, String? before}) async {
    final items = _posts
        .where((p) => authorId == null || p.authorId == authorId)
        .where((p) => !following || _following.contains(p.authorId))
        .where((p) => !_blocked.containsKey(p.authorId))
        .toList();
    return FeedPage(items, null);
  }

  @override
  Future<({bool empathized, int count})> toggleEmpathy(String postId) async {
    _guard();
    final i = _posts.indexWhere((p) => p.id == postId);
    if (i < 0 || _posts[i].isMine) throw const ApiException(404, 'not_found');
    final p = _posts[i];
    _posts[i] = p.copyWith(
      empathizedByMe: !p.empathizedByMe,
      empathyCount: p.empathyCount + (p.empathizedByMe ? -1 : 1),
    );
    return (empathized: _posts[i].empathizedByMe, count: _posts[i].empathyCount);
  }

  @override
  Future<PublishOutcome> publish({
    required String text,
    required TypingSession session,
    required String localDate,
  }) async {
    if (wantsHumanCheck) return const Rejected(RejectReason.humanCheck);
    final post = Post(
      id: 'local-${_next++}',
      authorId: _me.id,
      authorName: _me.displayName,
      authorHandle: _me.handle,
      body: text.trim(),
      lang: RegExp('[가-힣]').hasMatch(text) ? 'ko' : 'en',
      createdAt: _clock(),
      typingTime: session.activeDuration,
      empathyCount: 0,
      isMine: true,
    );
    _posts.insert(0, post);
    return _published(post, localDate);
  }

  @override
  Future<PublishOutcome> edit(
    String postId, {
    required String text,
    required TypingSession session,
    required String localDate,
  }) async {
    final i = _posts.indexWhere((p) => p.id == postId && p.isMine);
    if (i < 0) return const Rejected(RejectReason.notFound);
    final old = _posts[i];
    if (old.empathyCount > 0) return const Rejected(RejectReason.locked);
    _posts[i] = Post(
      id: old.id,
      authorId: old.authorId,
      authorName: old.authorName,
      authorHandle: old.authorHandle,
      body: text.trim(),
      lang: old.lang,
      createdAt: old.createdAt,
      editedAt: _clock(),
      typingTime: old.typingTime + session.activeDuration,
      empathyCount: 0,
      isMine: true,
    );
    return _published(_posts[i], localDate);
  }

  Published _published(Post post, String localDate) {
    if (_days.add(localDate)) {
      _me = _me.copyWith(writingDays: _me.writingDays + 1, followUnlocked: _me.writingDays + 1 >= _me.daysToFollow);
    }
    final firsts = <String>[];
    for (final phrase in demoPhrases(post.body)) {
      if (firsts.length == 3) break;
      if (_claimed.add(phrase.toLowerCase())) firsts.add(phrase);
    }
    return Published(
      postId: post.id,
      typingTime: post.typingTime,
      similarPeople: 4,
      showSimilar: true,
      firstPhrases: firsts,
      writingDays: _me.writingDays,
      followUnlocked: _me.followUnlocked,
    );
  }

  @override
  Future<void> delete(String postId) async => _posts.removeWhere((p) => p.id == postId && p.isMine);

  @override
  Future<void> follow(String userId) async {
    _guard();
    if (!_me.followUnlocked) throw const ApiException(403, 'not_allowed');
    _following.add(userId);
  }

  @override
  Future<void> unfollow(String userId) async => _following.remove(userId);

  /// Set to make the next guarded action ask for a typing check, as the
  /// server does when activity looks automated.
  bool wantsHumanCheck = false;

  void _guard() {
    if (wantsHumanCheck) throw const ApiException(428, 'human_check');
  }

  static const demoCheckPhrase = '오늘 하늘은 어제보다 조금 더 맑다';

  @override
  Future<Post> post(String postId, {required String lang}) async =>
      _posts.firstWhere((p) => p.id == postId, orElse: () => throw const ApiException(404, 'not_found'));

  @override
  Future<void> setBookmark(String postId, bool saved) async {
    final i = _posts.indexWhere((p) => p.id == postId);
    if (i < 0) throw const ApiException(404, 'not_found');
    _posts[i] = _posts[i].copyWith(bookmarked: saved);
    _savedOrder.remove(postId);
    if (saved) _savedOrder.insert(0, postId);
  }

  final List<String> _savedOrder = [];

  @override
  Future<List<Post>> bookmarks({required String lang}) async => [
    for (final id in _savedOrder) ..._posts.where((p) => p.id == id),
  ];

  @override
  Future<List<PersonHit>> searchPeople(String query) async {
    final q = query.replaceFirst('@', '').toLowerCase();
    final seen = <String>{};
    return [
      for (final p in _posts)
        if (!p.isMine &&
            !_blocked.containsKey(p.authorId) &&
            (p.authorHandle.toLowerCase().contains(q) || p.authorName.toLowerCase().contains(q)) &&
            seen.add(p.authorId))
          PersonHit(id: p.authorId, handle: p.authorHandle, displayName: p.authorName),
    ];
  }

  /// No embeddings here: posts that share a word with the query.
  @override
  Future<List<Post>> searchPosts(String query, {required String lang}) async {
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.length > 1).toList();
    return [
      for (final p in _posts)
        if (!_blocked.containsKey(p.authorId) && words.any((w) => p.body.toLowerCase().contains(w))) p,
    ];
  }

  @override
  Future<String> exportData() async => const JsonEncoder.withIndent('  ').convert({
    'profile': {'handle': _me.handle, 'displayName': _me.displayName, 'bio': _me.bio},
    'posts': [
      for (final p in _posts.where((p) => p.isMine))
        {'id': p.id, 'body': p.body, 'createdAt': p.createdAt.toIso8601String()},
    ],
  });

  @override
  Future<String> humanCheckPhrase(String lang) async => demoCheckPhrase;

  @override
  Future<void> passHumanCheck(String text, TypingSession session) async {
    if (text.trim() != demoCheckPhrase || session.events.isEmpty) throw const ApiException(400, 'not_human');
    wantsHumanCheck = false;
  }
}

/// Three-word windows within each sentence, for the demo only. The server
/// strips Korean particles and skips filler words.
List<String> demoPhrases(String text) {
  final out = <String>[];
  for (final sentence in text.split(RegExp(r'[.!?\n]+'))) {
    final words = sentence
        .split(RegExp(r'\s+'))
        .map((w) => w.replaceAll(RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true), ''))
        .where((w) => w.isNotEmpty)
        .toList();
    for (var k = 0; k + 3 <= words.length; k += 3) {
      out.add(words.sublist(k, k + 3).join(' '));
    }
  }
  return out;
}

List<Post> _samplePosts(DateTime now) => [
  Post(
    id: 'p1',
    authorId: 'u-yoonseo-friend',
    authorName: '서하',
    authorHandle: 'seoha',
    body: '오늘은 아무 말도 하지 않은 시간이 가장 길었다. 그런데 이상하게 그 시간에 나를 가장 많이 들은 것 같다.',
    lang: 'ko',
    createdAt: now.subtract(const Duration(hours: 2)),
    typingTime: const Duration(minutes: 2, seconds: 18),
    empathyCount: 24,
  ),
  Post(
    id: 'p2',
    authorId: 'u-daniel',
    authorName: 'Daniel',
    authorHandle: 'daniel.k',
    body: "We don't move because we are sure. We become sure after we move.",
    translation: '우리는 확신이 있어서 움직이는 게 아니라, 움직이고 나서야 확신을 만든다고 생각한다.',
    lang: 'en',
    createdAt: now.subtract(const Duration(hours: 3)),
    typingTime: const Duration(minutes: 1, seconds: 5),
    empathyCount: 9,
    empathizedByMe: true,
  ),
  Post(
    id: 'p3',
    authorId: 'u-haru',
    authorName: '하루',
    authorHandle: 'haru',
    body: '지하철에서 모르는 사람이 내 어깨에 기대 잠들었다. 깨우지 않았다. 나도 그렇게 기대고 싶었던 날이 있었으니까.',
    lang: 'ko',
    createdAt: now.subtract(const Duration(hours: 5)),
    typingTime: const Duration(minutes: 3, seconds: 41),
    empathyCount: 51,
  ),
];
