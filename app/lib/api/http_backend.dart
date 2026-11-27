import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core/typing_session.dart';
import '../models/admin.dart';
import '../models/growth.dart';
import '../models/post.dart';
import '../models/profile.dart';
import '../models/publish_outcome.dart';
import '../models/social.dart';
import 'backend.dart';
import 'cognito_auth.dart';

/// The Saenggak API on AWS. Every request carries the Cognito access token.
class HttpBackend implements Backend {
  HttpBackend({required String baseUrl, required this.auth, http.Client? client})
    : _base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
      _client = client ?? http.Client();

  final Uri _base;
  final CognitoAuth auth;
  final http.Client _client;

  @override
  String get myId => auth.userId;

  Future<http.Response> _send(String method, String path, {Map<String, String>? query, Object? body}) async {
    var uri = _base.resolve(path);
    if (query != null) uri = uri.replace(queryParameters: query);
    Future<http.Response> attempt() async {
      final req = http.Request(method, uri)
        ..headers['authorization'] = 'Bearer ${await auth.accessToken()}'
        ..headers['content-type'] = 'application/json';
      if (body != null) req.body = jsonEncode(body);
      return http.Response.fromStream(await _client.send(req));
    }

    var res = await attempt();
    if (res.statusCode == 401) {
      await auth.refresh();
      res = await attempt();
    }
    return res;
  }

  /// The body as JSON. A page that is not JSON, such as the firewall's or
  /// CloudFront's own error page, reads as empty so the status decides.
  Map<String, dynamic> _json(http.Response res) {
    if (res.body.isEmpty) return <String, dynamic>{};
    try {
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      return j is Map<String, dynamic> ? j : <String, dynamic>{};
    } on FormatException {
      return <String, dynamic>{};
    }
  }

  Map<String, dynamic> _ok(http.Response res) {
    final j = _json(res);
    if (res.statusCode >= 300) throw ApiException(res.statusCode, j['error'] as String? ?? 'unknown');
    return j;
  }

  @override
  Future<Profile?> me() async {
    final res = await _send('GET', 'me');
    if (res.statusCode == 404) return null;
    return Profile.fromJson(_ok(res));
  }

  @override
  Future<Profile> saveProfile({
    required String handle,
    required String displayName,
    String bio = '',
    required String locale,
    required String timeZone,
  }) async => Profile.fromJson(
    _ok(
      await _send(
        'PUT',
        'me',
        body: {'handle': handle, 'displayName': displayName, 'bio': bio, 'locale': locale, 'timeZone': timeZone},
      ),
    ),
  );

  @override
  Future<Profile> setPhoto(Uint8List jpeg) async {
    final res = await _send('PUT', 'me/photo', body: {'jpeg': base64Encode(jpeg)});
    final j = _json(res);
    if (res.statusCode >= 300) {
      final code = j['error'] == 'photo_refused' ? j['problem'] : j['error'];
      throw ApiException(res.statusCode, code as String? ?? 'unknown');
    }
    return Profile.fromJson(j);
  }

  @override
  Future<void> signOut() => auth.signOut();

  @override
  Future<void> deleteAccount() async {
    _ok(await _send('DELETE', 'me'));
    await auth.signOut();
  }

  @override
  Future<void> report({String? postId, String? userId, required String reason, String note = ''}) async => _ok(
    await _send(
      'POST',
      postId != null ? 'posts/$postId/report' : 'users/$userId/report',
      body: {'reason': reason, 'note': note},
    ),
  );

  @override
  Future<void> block(String userId) async => _ok(await _send('PUT', 'users/$userId/block'));

  @override
  Future<void> unblock(String userId) async => _ok(await _send('DELETE', 'users/$userId/block'));

  @override
  Future<List<BlockedUser>> blockedUsers() async => (_ok(await _send('GET', 'me/blocks'))['items'] as List)
      .cast<Map<String, dynamic>>()
      .map(BlockedUser.fromJson)
      .toList();

  @override
  Future<NotificationsPage> notifications({String? before}) async {
    final j = _ok(await _send('GET', 'notifications', query: {'before': ?before}));
    return NotificationsPage(
      (j['items'] as List).cast<Map<String, dynamic>>().map(AppNotification.fromJson).toList(),
      (j['unread'] as num? ?? 0).toInt(),
      j['next'] as String?,
    );
  }

  @override
  Future<void> markNotificationsSeen() async => _ok(await _send('POST', 'notifications/seen'));

  @override
  Future<List<OpenReport>> openReports() async => (_ok(await _send('GET', 'admin/reports'))['items'] as List)
      .cast<Map<String, dynamic>>()
      .map(OpenReport.fromJson)
      .toList();

  @override
  Future<void> resolveReport(String reportId, {String note = ''}) async =>
      _ok(await _send('POST', 'admin/reports/$reportId/resolve', body: {'note': note}));

  @override
  Future<AdminStats> adminStats() async => AdminStats.fromJson(_ok(await _send('GET', 'admin/stats')));

  @override
  Future<List<ReviewItem>> reviewQueue() async => (_ok(await _send('GET', 'admin/review'))['items'] as List)
      .cast<Map<String, dynamic>>()
      .map(ReviewItem.fromJson)
      .toList();

  @override
  Future<void> reviewPost(String postId, {required bool publish}) async =>
      _ok(await _send('POST', 'admin/posts/$postId/review', body: {'decision': publish ? 'publish' : 'keep_blocked'}));

  @override
  Future<void> removePost(String postId, {String note = ''}) async =>
      _ok(await _send('POST', 'admin/posts/$postId/remove', body: {'note': note}));

  @override
  Future<List<AdminUser>> searchUsers(String query) async =>
      (_ok(await _send('GET', 'admin/users', query: {'q': query}))['items'] as List)
          .cast<Map<String, dynamic>>()
          .map(AdminUser.fromJson)
          .toList();

  @override
  Future<void> setSuspended(String userId, {required bool suspended, String reason = ''}) async =>
      _ok(await _send('PUT', 'admin/users/$userId/suspension', body: {'suspended': suspended, 'reason': reason}));

  @override
  Future<void> removePhoto(String userId) async => _ok(await _send('DELETE', 'admin/users/$userId/photo'));

  @override
  Future<Profile> user(String id) async => Profile.fromJson(_ok(await _send('GET', 'users/$id')));

  @override
  Future<FeedPage> feed({required String lang, bool following = false, String? authorId, String? before}) async {
    final j = _ok(
      await _send(
        'GET',
        'feed',
        query: {'lang': lang, 'tab': following ? 'following' : 'all', 'author': ?authorId, 'before': ?before},
      ),
    );
    return FeedPage(_posts(j), j['next'] as String?);
  }

  @override
  Future<({bool empathized, int count})> toggleEmpathy(String postId) async {
    final j = _ok(await _send('POST', 'posts/$postId/empathy'));
    return (empathized: j['empathized'] as bool, count: (j['count'] as num).toInt());
  }

  Future<PublishOutcome> _write(
    String method,
    String path,
    String text,
    TypingSession session,
    String localDate,
  ) async {
    final http.Response res;
    try {
      res = await _send(method, path, body: {'text': text, 'session': session.toJson(), 'localDate': localDate});
    } on http.ClientException {
      return const Rejected(RejectReason.network);
    }
    if (res.statusCode == 200 || res.statusCode == 201) return Published.fromJson(_json(res));
    return Rejected.fromJson(res.statusCode, _json(res));
  }

  @override
  Future<PublishOutcome> publish({required String text, required TypingSession session, required String localDate}) =>
      _write('POST', 'posts', text, session, localDate);

  @override
  Future<PublishOutcome> edit(
    String postId, {
    required String text,
    required TypingSession session,
    required String localDate,
  }) => _write('PATCH', 'posts/$postId', text, session, localDate);

  @override
  Future<void> delete(String postId) async => _ok(await _send('DELETE', 'posts/$postId'));

  List<Post> _posts(Map<String, dynamic> j) =>
      (j['items'] as List).cast<Map<String, dynamic>>().map((p) => Post.fromJson(p, myId: myId)).toList();

  @override
  Future<Post> post(String postId, {required String lang}) async =>
      Post.fromJson(_ok(await _send('GET', 'posts/$postId', query: {'lang': lang})), myId: myId);

  @override
  Future<void> setBookmark(String postId, bool saved) async =>
      _ok(await _send(saved ? 'PUT' : 'DELETE', 'posts/$postId/bookmark'));

  @override
  Future<List<Post>> bookmarks({required String lang}) async =>
      _posts(_ok(await _send('GET', 'bookmarks', query: {'lang': lang})));

  @override
  Future<List<PersonHit>> searchPeople(String query) async =>
      (_ok(await _send('GET', 'search/users', query: {'q': query}))['items'] as List)
          .cast<Map<String, dynamic>>()
          .map(PersonHit.fromJson)
          .toList();

  @override
  Future<List<Post>> searchPosts(String query, {required String lang}) async =>
      _posts(_ok(await _send('GET', 'search/posts', query: {'q': query, 'lang': lang})));

  @override
  Future<String> exportData() async {
    final res = await _send('GET', 'me/export');
    _ok(res);
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  @override
  Future<String> humanCheckPhrase(String lang) async =>
      _ok(await _send('GET', 'me/human-check', query: {'lang': lang}))['phrase'] as String;

  @override
  Future<void> passHumanCheck(String text, TypingSession session) async =>
      _ok(await _send('POST', 'me/human-check', body: {'text': text, 'session': session.toJson()}));

  @override
  Future<void> follow(String userId) async => _ok(await _send('PUT', 'users/$userId/follow'));

  @override
  Future<void> unfollow(String userId) async => _ok(await _send('DELETE', 'users/$userId/follow'));

  @override
  Future<void> setPostAlerts(String userId, bool on) async =>
      _ok(await _send(on ? 'PUT' : 'DELETE', 'users/$userId/alerts'));

  @override
  Future<SharingSettings> sharing() async => SharingSettings.fromJson(_ok(await _send('GET', 'me/sharing')));

  @override
  Future<SharingSettings> setSharing({required bool shareOk, required bool anonymous}) async =>
      SharingSettings.fromJson(
        _ok(await _send('PUT', 'me/sharing', body: {'shareOk': shareOk, 'anonymous': anonymous})),
      );

  @override
  Future<void> setPostSharing(String postId, {required bool excluded}) async =>
      _ok(await _send('PUT', 'posts/$postId/sharing', body: {'excluded': excluded}));

  @override
  Future<Invite> invite() async => Invite.fromJson(_ok(await _send('GET', 'me/invite')));

  @override
  Future<void> recordSource(String code) async => _ok(await _send('POST', 'me/source', body: {'code': code}));

  @override
  Future<DailyQuestion?> todayQuestion() async {
    final q = _ok(await _send('GET', 'questions/today'))['question'] as Map<String, dynamic>?;
    return q == null ? null : DailyQuestion(ko: q['ko'] as String, en: q['en'] as String);
  }

  @override
  Future<Dashboard> adminDashboard({int days = 30}) async =>
      Dashboard.fromJson(_ok(await _send('GET', 'admin/dashboard', query: {'days': '$days'})));

  @override
  Future<List<AuditEntry>> adminAudit({DateTime? before}) async =>
      (_ok(
                await _send(
                  'GET',
                  'admin/audit',
                  query: before == null ? null : {'before': before.toUtc().toIso8601String()},
                ),
              )['items']
              as List)
          .cast<Map<String, dynamic>>()
          .map(AuditEntry.fromJson)
          .toList();

  @override
  Future<PromoPage> promoItems(String tab) async {
    final j = _ok(await _send('GET', 'admin/promo', query: {'tab': tab}));
    return PromoPage(
      (j['items'] as List).cast<Map<String, dynamic>>().map(PromoItem.fromJson).toList(),
      (j['channels'] as List? ?? const []).cast<String>(),
    );
  }

  @override
  Future<int> runPromoPick() async => (_ok(await _send('POST', 'admin/promo/run'))['added'] as num).toInt();

  @override
  Future<void> decidePromo(
    String itemId, {
    required bool approve,
    String? caption,
    Uint8List? png,
    DateTime? at,
  }) async => _ok(
    await _send(
      'POST',
      'admin/promo/$itemId/decision',
      body: {
        'approve': approve,
        'caption': ?caption,
        if (png != null) 'png': base64Encode(png),
        if (at != null) 'scheduledFor': at.toUtc().toIso8601String(),
      },
    ),
  );

  @override
  Future<void> markPromo(String itemId, String status) async =>
      _ok(await _send('POST', 'admin/promo/$itemId/mark', body: {'status': status}));

  @override
  Future<List<LinkStat>> linkStats() async => (_ok(await _send('GET', 'admin/links'))['items'] as List)
      .cast<Map<String, dynamic>>()
      .map(LinkStat.fromJson)
      .toList();

  @override
  Future<void> createLink({required String code, required String channel, String label = ''}) async =>
      _ok(await _send('POST', 'admin/links', body: {'code': code, 'channel': channel, 'label': label}));

  @override
  Future<List<AdminQuestion>> adminQuestions() async => (_ok(await _send('GET', 'admin/questions'))['items'] as List)
      .cast<Map<String, dynamic>>()
      .map(AdminQuestion.fromJson)
      .toList();

  @override
  Future<AdminQuestion> saveQuestion(
    String day, {
    required String textKo,
    required String textEn,
    required bool approve,
  }) async => AdminQuestion.fromJson(
    _ok(await _send('PUT', 'admin/questions/$day', body: {'textKo': textKo, 'textEn': textEn, 'approve': approve})),
  );
}
