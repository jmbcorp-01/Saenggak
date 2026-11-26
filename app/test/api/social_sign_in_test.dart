import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saenggak/api/cognito_auth.dart';
import 'package:saenggak/api/config.dart';
import 'package:saenggak/api/token_store.dart';

const config = ApiConfig(
  apiUrl: 'https://saenggak.app/api',
  region: 'us-east-1',
  clientId: 'client',
  authDomain: 'auth.saenggak.app',
  signInWith: ['google', 'apple'],
);

String token(String sub) {
  String part(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part({'sub': sub})}.sig';
}

void main() {
  late List<Uri> opened;
  late List<Map<String, String>> exchanges;
  late String Function(Uri url) answer;
  late MemoryTokenStore store;
  late CognitoAuth auth;

  setUp(() {
    opened = [];
    exchanges = [];
    store = MemoryTokenStore();
    final client = MockClient((req) async {
      expect(req.url.toString(), 'https://auth.saenggak.app/oauth2/token');
      exchanges.add(Uri.splitQueryString(req.body));
      return http.Response(
        jsonEncode({'access_token': token('user-1'), 'refresh_token': 'r1', 'expires_in': 3600}),
        200,
      );
    });
    auth = CognitoAuth(
      config,
      client: client,
      store: store,
      redirect: Uri.parse('saenggak://auth'),
      browser: (url, scheme) async {
        expect(scheme, 'saenggak');
        opened.add(url);
        return answer(url);
      },
    );
  });

  String ok(Uri url) => 'saenggak://auth?code=abc&state=${url.queryParameters['state']}';

  test('signs in with Google through the sign-in pages, with PKCE', () async {
    answer = ok;
    await auth.signInWith('google');

    final url = opened.single;
    expect(url.host, 'auth.saenggak.app');
    expect(url.path, '/oauth2/authorize');
    expect(url.queryParameters['identity_provider'], 'Google');
    expect(url.queryParameters['redirect_uri'], 'saenggak://auth');
    final sent = exchanges.single;
    expect(sent['code'], 'abc');
    final challenge = base64Url.encode(sha256.convert(ascii.encode(sent['code_verifier']!)).bytes).replaceAll('=', '');
    expect(url.queryParameters['code_challenge'], challenge);
    expect(auth.signedIn, isTrue);
    expect(auth.userId, 'user-1');
    expect(store.token, 'r1');
  });

  test('asks Apple for SignInWithApple', () async {
    answer = ok;
    await auth.signInWith('apple');
    expect(opened.single.queryParameters['identity_provider'], 'SignInWithApple');
  });

  test('tries once more when the first sign-in joined an existing account', () async {
    var first = true;
    answer = (url) {
      if (!first) return ok(url);
      first = false;
      return 'saenggak://auth?error_description=Already+found+an+entry+for+username+Google_1&error=invalid_request';
    };
    await auth.signInWith('google');
    expect(opened, hasLength(2));
    expect(auth.signedIn, isTrue);
  });

  test('refuses an answer for another sign-in attempt', () async {
    answer = (url) => 'saenggak://auth?code=abc&state=someone-else';
    await expectLater(auth.signInWith('google'), throwsA(isA<AuthException>()));
    expect(exchanges, isEmpty);
    expect(auth.signedIn, isFalse);
  });

  test('reports a closed window as cancelled', () async {
    answer = (url) => throw Exception('CANCELED');
    await expectLater(
      auth.signInWith('google'),
      throwsA(isA<AuthException>().having((e) => e.type, 'type', 'Cancelled')),
    );
  });

  test('offers Google and Apple only when the sign-in pages are set up', () {
    expect(config.socialProviders, ['google', 'apple']);
    expect(const ApiConfig(apiUrl: 'x', region: 'r', clientId: 'c', signInWith: ['google']).socialProviders, isEmpty);
    final fromJson = ApiConfig.fromJson({
      'apiUrl': 'x',
      'cognitoClientId': 'c',
      'authDomain': 'auth.saenggak.app',
      'signInWith': ['apple'],
    });
    expect(fromJson.socialProviders, ['apple']);
  });
}
