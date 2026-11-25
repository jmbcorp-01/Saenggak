import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core/typing_session.dart';
import '../models/post.dart';
import '../models/profile.dart';
import '../models/publish_outcome.dart';
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

  Map<String, dynamic> _json(http.Response res) =>
      res.body.isEmpty ? <String, dynamic>{} : jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;

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
    final items = (j['items'] as List).cast<Map<String, dynamic>>().map((p) => Post.fromJson(p, myId: myId)).toList();
    return FeedPage(items, j['next'] as String?);
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

  @override
  Future<void> follow(String userId) async => _ok(await _send('PUT', 'users/$userId/follow'));

  @override
  Future<void> unfollow(String userId) async => _ok(await _send('DELETE', 'users/$userId/follow'));
}
