import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saenggak/api/backend.dart';
import 'package:saenggak/api/cognito_auth.dart';
import 'package:saenggak/api/config.dart';
import 'package:saenggak/api/http_backend.dart';
import 'package:saenggak/core/typing_session.dart';
import 'package:saenggak/models/publish_outcome.dart';

const config = ApiConfig(apiUrl: 'https://api.example.com', region: 'us-east-1', clientId: 'client');

/// A JWT with the given subject. Signature is not checked by the app.
String token(String sub) {
  String part(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part({'sub': sub})}.sig';
}

/// Answers Cognito sign-in with fresh tokens each time, and counts refreshes.
class FakeCognito {
  int refreshes = 0;
  http.Response handle(http.Request req) {
    final target = req.headers['x-amz-target']!;
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    if (target.endsWith('InitiateAuth')) {
      if (body['AuthFlow'] == 'REFRESH_TOKEN_AUTH') refreshes++;
      if (body['AuthParameters']['PASSWORD'] == 'wrong') {
        return http.Response(jsonEncode({'__type': 'NotAuthorizedException', 'message': 'x'}), 400);
      }
      return http.Response(
        jsonEncode({
          'AuthenticationResult': {'AccessToken': token('user-1'), 'RefreshToken': 'r', 'ExpiresIn': 3600},
        }),
        200,
      );
    }
    return http.Response('{}', 200);
  }
}

void main() {
  late FakeCognito cognito;
  late List<http.Request> apiCalls;
  late http.Response Function(http.Request) api;
  late HttpBackend backend;

  setUp(() async {
    cognito = FakeCognito();
    apiCalls = [];
    final client = MockClient((req) async {
      if (req.url.host.startsWith('cognito-idp')) return cognito.handle(req);
      apiCalls.add(req);
      return api(req);
    });
    final auth = CognitoAuth(config, client: client);
    await auth.signIn('a@b.c', 'secret-password');
    backend = HttpBackend(baseUrl: config.apiUrl, auth: auth, client: client);
  });

  test('signs in and reads the user id from the token', () {
    expect(backend.myId, 'user-1');
  });

  test('maps Cognito errors to messages', () async {
    final auth = CognitoAuth(config, client: MockClient((req) async => cognito.handle(req)));
    await expectLater(
      auth.signIn('a@b.c', 'wrong'),
      throwsA(isA<AuthException>().having((e) => e.message, 'message', '이메일이나 비밀번호가 맞지 않아요.')),
    );
  });

  test('publishes with the session and parses the extras', () async {
    api = (_) => http.Response.bytes(
      utf8.encode(
        jsonEncode({
          'id': 'p1',
          'typingMs': 61000,
          'similar': {'people': 12, 'show': true},
          'firstPhrases': ['기대고 싶었던 날'],
          'writingDays': 4,
          'followUnlocked': false,
        }),
      ),
      201,
    );
    final session = TypingSession()..record(inserted: 1, deleted: 0);
    final out = await backend.publish(text: '글', session: session, localDate: '2026-11-25');

    final req = apiCalls.single;
    expect(req.method, 'POST');
    expect(req.url.toString(), 'https://api.example.com/posts');
    expect(req.headers['authorization'], startsWith('Bearer '));
    final sent = jsonDecode(req.body) as Map<String, dynamic>;
    expect(sent['localDate'], '2026-11-25');
    expect((sent['session'] as Map)['events'], hasLength(1));

    expect(out, isA<Published>());
    final p = out as Published;
    expect(p.similarPeople, 12);
    expect(p.firstPhrases, ['기대고 싶었던 날']);
    expect(p.typingTime, const Duration(seconds: 61));
  });

  test('uploads the photo as base64 and reads the new photo URL', () async {
    api = (_) => http.Response(
      jsonEncode({'id': 'user-1', 'handle': 'me', 'displayName': 'Me', 'photoUrl': 'https://cdn.example/photos/a.jpg'}),
      200,
    );
    final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 1, 2]);
    final me = await backend.setPhoto(jpeg);

    final req = apiCalls.single;
    expect(req.method, 'PUT');
    expect(req.url.toString(), 'https://api.example.com/me/photo');
    expect((jsonDecode(req.body) as Map)['jpeg'], base64Encode(jpeg));
    expect(me.photoUrl, 'https://cdn.example/photos/a.jpg');
  });

  test('a refused photo throws with the reason', () async {
    api = (_) => http.Response(jsonEncode({'error': 'photo_refused', 'problem': 'many_faces'}), 422);
    await expectLater(
      backend.setPhoto(Uint8List.fromList([0xFF, 0xD8, 0xFF])),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'many_faces')),
    );
  });

  test('turns a blocked post into a message', () async {
    api = (_) => http.Response(jsonEncode({'error': 'blocked', 'reason': 'profanity'}), 422);
    final out = await backend.publish(text: '글', session: TypingSession(), localDate: '2026-11-25');
    expect((out as Rejected).message, '욕설이나 비하 표현이 있어 올리지 않았어요.');
  });

  test('explains the hourly limit and a filter outage', () async {
    for (final (status, code, reason) in [
      (429, 'rate_limited', RejectReason.rateLimited),
      (503, 'filter_unavailable', RejectReason.filterUnavailable),
      (409, 'profile_required', RejectReason.profileRequired),
    ]) {
      api = (_) => http.Response(jsonEncode({'error': code}), status);
      final out = await backend.publish(text: '글', session: TypingSession(), localDate: '2026-11-25');
      expect((out as Rejected).reason, reason);
    }
  });

  test('edit uses PATCH and reports a locked post', () async {
    api = (_) => http.Response(jsonEncode({'error': 'locked'}), 409);
    final out = await backend.edit('p1', text: '글', session: TypingSession(), localDate: '2026-11-25');
    expect(apiCalls.single.method, 'PATCH');
    expect(apiCalls.single.url.path, '/posts/p1');
    expect((out as Rejected).reason, RejectReason.locked);
  });

  test('reads the feed with translations and Postgres timestamps', () async {
    api = (_) => http.Response.bytes(
      utf8.encode(
        jsonEncode({
          'items': [
            {
              'id': 'p1',
              'authorId': 'user-2',
              'authorHandle': 'dan',
              'authorName': 'Dan',
              'photoKey': null,
              'body': 'Hello there',
              'lang': 'en',
              'typingMs': 5000,
              'empathyCount': 0,
              'empathizedByMe': false,
              'createdAt': '2026-11-25 01:02:03.456+00',
              'editedAt': null,
              'translation': {'lang': 'ko', 'body': '안녕하세요'},
            },
          ],
          'next': null,
        }),
      ),
      200,
    );
    final page = await backend.feed(lang: 'ko', following: true, before: '2026-11-25T00:00:00Z');
    expect(apiCalls.single.url.queryParameters, {'lang': 'ko', 'tab': 'following', 'before': '2026-11-25T00:00:00Z'});
    final post = page.items.single;
    expect(post.translation, '안녕하세요');
    expect(post.createdAt, DateTime.utc(2026, 11, 25, 1, 2, 3, 456));
    expect(post.isMine, isFalse);
  });

  test('refreshes the token once on 401', () async {
    var first = true;
    api = (_) {
      if (first) {
        first = false;
        return http.Response('{"message":"Unauthorized"}', 401);
      }
      return http.Response(jsonEncode({'empathized': true, 'count': 3}), 200);
    };
    final r = await backend.toggleEmpathy('p1');
    expect(r.count, 3);
    expect(cognito.refreshes, 1);
    expect(apiCalls, hasLength(2));
  });

  test('a new account has no profile yet', () async {
    api = (_) => http.Response(jsonEncode({'error': 'not_found'}), 404);
    expect(await backend.me(), isNull);
  });
}
