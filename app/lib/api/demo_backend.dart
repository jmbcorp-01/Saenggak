import 'dart:convert';
import 'dart:typed_data';

import '../core/weighted_length.dart';
import '../core/typing_session.dart';
import '../models/admin.dart';
import '../models/growth.dart';
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
      alertsOn: _alerts.contains(id),
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
      body: WeightedLength.tidy(text),
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
      body: WeightedLength.tidy(text),
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
  Future<void> unfollow(String userId) async {
    _following.remove(userId);
    _alerts.remove(userId);
  }

  final Set<String> _alerts = {};

  @override
  Future<void> setPostAlerts(String userId, bool on) async {
    if (!_following.contains(userId)) throw const ApiException(404, 'not_following');
    on ? _alerts.add(userId) : _alerts.remove(userId);
  }

  /// A new post by someone else, as if they just wrote it. For trying out the
  /// new-posts button and alerts.
  void arrive(Post post) {
    _posts.insert(0, post);
    if (_alerts.contains(post.authorId)) {
      notificationItems.insert(
        0,
        AppNotification(
          kind: 'post',
          at: post.createdAt,
          actorId: post.authorId,
          actorHandle: post.authorHandle,
          actorName: post.authorName,
          postId: post.id,
          excerpt: post.body.length > 60 ? post.body.substring(0, 60) : post.body,
        ),
      );
    }
  }

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

  // ---- Growth: sharing, invites, the daily question and the admin side ----

  SharingSettings _sharing = const SharingSettings();
  final Set<String> excludedPosts = {};
  String? recordedSource;
  final Map<String, PromoItem> _promo = {};
  final Map<String, AdminQuestion> _questions = {};
  final List<LinkStat> _links = [
    const LinkStat(code: '*', channel: 'invite', clicks: 42, signups: 9, active7: 6),
    const LinkStat(code: 'disquiet', channel: 'community', label: '디스콰이엇 런칭', clicks: 120, signups: 14, active7: 8),
  ];
  final List<AuditEntry> _audit = [];

  /// Today's question in the demo, or none.
  DailyQuestion? question = const DailyQuestion(
    ko: '오늘 가장 오래 생각한 사람은 누구인가요?',
    en: 'Who did you think about most today?',
  );

  void _log(String action, String target) => _audit.insert(
    0,
    AuditEntry(id: '${_audit.length}', adminHandle: _me.handle, action: action, targetId: target, at: _clock()),
  );

  @override
  Future<SharingSettings> sharing() async => _sharing;

  @override
  Future<SharingSettings> setSharing({required bool shareOk, required bool anonymous}) async =>
      _sharing = SharingSettings(shareOk: shareOk, anonymous: anonymous);

  @override
  Future<void> setPostSharing(String postId, {required bool excluded}) async {
    final i = _posts.indexWhere((p) => p.id == postId && p.authorId == _me.id);
    if (i < 0) throw const ApiException(404, 'not_found');
    excluded ? excludedPosts.add(postId) : excludedPosts.remove(postId);
    _posts[i] = _posts[i].copyWith(shareExcluded: excluded);
  }

  @override
  Future<Invite> invite() async => const Invite(code: 'SAENG2K7', url: 'https://saenggak.app/i/SAENG2K7');

  @override
  Future<void> recordSource(String code) async {
    if (code.toUpperCase() != 'SAENG2K7' && code.toLowerCase() != 'disquiet') {
      throw const ApiException(404, 'unknown_code');
    }
    recordedSource = code;
  }

  /// Devices registered for push in the demo, token to platform.
  final Map<String, String> pushTokens = {};
  PushSettings _push = const PushSettings();

  @override
  Future<void> registerPush(String token, String platform) async => pushTokens[token] = platform;

  @override
  Future<void> unregisterPush(String token) async => pushTokens.remove(token);

  @override
  Future<PushSettings> pushSettings() async => _push;

  @override
  Future<PushSettings> setPushSettings(PushSettings settings) async => _push = settings;

  @override
  Future<DailyQuestion?> todayQuestion() async => question;

  @override
  Future<Dashboard> adminDashboard({int days = 30}) async {
    final today = _clock();
    return Dashboard(
      days: [
        for (var i = days - 1; i >= 0; i--)
          DashboardDay(
            day: localDateOf(today.subtract(Duration(days: i))),
            signups: 3 + (i * 7) % 11,
            posts: 8 + (i * 5) % 17,
            empathies: 20 + (i * 13) % 31,
            activePeople: 10 + (i * 3) % 9,
          ),
      ],
      d1: const Retention(rate: 0.46, cohort: 210),
      d7: const Retention(rate: 0.27, cohort: 160),
      d30: const Retention(rate: 0.14, cohort: 60),
      sources: const [
        SourceStat(channel: 'direct', signups: 140, active7: 31),
        SourceStat(channel: 'promo', signups: 22, active7: 9),
        SourceStat(channel: 'community', signups: 14, active7: 8),
        SourceStat(channel: 'invite', signups: 9, active7: 6),
      ],
    );
  }

  @override
  Future<List<AuditEntry>> adminAudit({DateTime? before}) async => List.of(_audit);

  void _seedPromo() {
    if (_promo.isNotEmpty) return;
    for (final p in _posts.where((p) => p.authorId != _me.id).take(3)) {
      final id = 'promo-${p.id}';
      _promo[id] = PromoItem(
        id: id,
        status: 'pending',
        caption: p.lang == 'ko'
            ? '오늘 생각에서 많은 공감을 받은 생각입니다. 당신의 생각도 직접 써 보세요. #생각 #오늘의생각'
            : 'One of today’s most felt thoughts on Saenggak. Write your own, by hand. #saenggak',
        linkCode: 'p-${p.id}',
        post: PromoPost(
          body: p.body,
          lang: p.lang,
          authorHandle: p.authorHandle,
          authorName: p.authorName,
          empathyCount: p.empathyCount,
          typingMs: p.typingTime.inMilliseconds,
        ),
      );
    }
  }

  static const _tabs = {
    'pending': ['pending'],
    'scheduled': ['approved', 'failed', 'takedown'],
    'done': ['posted', 'skipped', 'withdrawn'],
  };

  @override
  Future<PromoPage> promoItems(String tab) async {
    _seedPromo();
    final statuses = _tabs[tab] ?? const ['pending'];
    return PromoPage(_promo.values.where((i) => statuses.contains(i.status)).toList(), const []);
  }

  @override
  Future<int> runPromoPick() async {
    final before = _promo.length;
    _seedPromo();
    return _promo.length - before;
  }

  /// The last card image an admin approved, for tests.
  Uint8List? lastCard;

  @override
  Future<void> decidePromo(
    String itemId, {
    required bool approve,
    String? caption,
    Uint8List? png,
    DateTime? at,
  }) async {
    final i = _promo[itemId];
    if (i == null) throw const ApiException(404, 'not_found');
    if (png != null) lastCard = png;
    _promo[itemId] = PromoItem(
      id: i.id,
      status: approve ? 'approved' : 'skipped',
      caption: caption ?? i.caption,
      linkCode: i.linkCode,
      post: i.post,
      scheduledFor: approve ? (at ?? _clock().add(const Duration(hours: 3))) : null,
    );
    _log(approve ? 'promo_approve' : 'promo_skip', itemId);
  }

  @override
  Future<void> markPromo(String itemId, String status) async {
    final i = _promo[itemId];
    if (i == null) throw const ApiException(404, 'not_found');
    _promo[itemId] = PromoItem(id: i.id, status: status, caption: i.caption, linkCode: i.linkCode, post: i.post);
    _log('promo_$status', itemId);
  }

  @override
  Future<List<LinkStat>> linkStats() async => List.of(_links);

  @override
  Future<void> createLink({required String code, required String channel, String label = ''}) async {
    if (_links.any((l) => l.code == code)) throw const ApiException(409, 'taken');
    _links.add(LinkStat(code: code, channel: channel, label: label));
    _log('link_code', code);
  }

  @override
  Future<List<AdminQuestion>> adminQuestions() async {
    if (_questions.isEmpty) {
      final today = _clock();
      const drafts = [
        ('요즘 자주 듣는 노래에 담긴 기억은?', 'What memory lives in a song you play a lot lately?'),
        ('어릴 때 살던 동네에서 가장 먼저 떠오르는 곳은?', 'What place comes first to mind from where you grew up?'),
        ('오늘 누군가에게 고마웠던 순간은?', 'When were you grateful to someone today?'),
      ];
      for (var i = 0; i < drafts.length; i++) {
        final day = localDateOf(today.add(Duration(days: i + 1)));
        _questions[day] = AdminQuestion(day: day, textKo: drafts[i].$1, textEn: drafts[i].$2, approved: i == 0);
      }
    }
    return _questions.values.toList()..sort((a, b) => a.day.compareTo(b.day));
  }

  @override
  Future<AdminQuestion> saveQuestion(
    String day, {
    required String textKo,
    required String textEn,
    required bool approve,
  }) async {
    _log(approve ? 'question_approved' : 'question_draft', day);
    return _questions[day] = AdminQuestion(day: day, textKo: textKo, textEn: textEn, approved: approve);
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
