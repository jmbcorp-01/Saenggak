import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

import '../l10n/l10n.dart';
import 'config.dart';
import 'token_store.dart';

/// Opens [url] in the system's sign-in browser and returns the address it
/// came back to, which starts with [callbackScheme].
typedef WebAuthenticator = Future<String> Function(Uri url, String callbackScheme);

Future<String> _systemBrowser(Uri url, String callbackScheme) =>
    FlutterWebAuth2.authenticate(url: url.toString(), callbackUrlScheme: callbackScheme);

/// Where Cognito's sign-in pages send people back to.
Uri defaultRedirect() => kIsWeb ? Uri.base.resolve('/auth.html') : Uri.parse('saenggak://auth');

/// Email sign-up and sign-in with Amazon Cognito, called directly over HTTPS.
/// These Cognito operations are public, so no AWS signing is needed. Google
/// and Apple go through Cognito's sign-in pages in the system browser.
class CognitoAuth {
  CognitoAuth(
    this.config, {
    http.Client? client,
    DateTime Function()? clock,
    TokenStore? store,
    WebAuthenticator? browser,
    Uri? redirect,
  }) : _client = client ?? http.Client(),
       _clock = clock ?? DateTime.now,
       _store = store ?? MemoryTokenStore(),
       _browser = browser ?? _systemBrowser,
       _redirect = redirect ?? defaultRedirect();

  final ApiConfig config;
  final TokenStore _store;
  final http.Client _client;
  final DateTime Function() _clock;
  final WebAuthenticator _browser;
  final Uri _redirect;

  String? _accessToken;
  String? _refreshToken;
  DateTime? _expiresAt;
  String? _userId;

  bool get signedIn => _accessToken != null;

  /// Cognito's "sub", the id the server uses for this user.
  String get userId => _userId ?? (throw StateError('not signed in'));

  Uri get _endpoint => Uri.parse('https://cognito-idp.${config.region}.amazonaws.com/');

  Future<Map<String, dynamic>> _call(String op, Map<String, Object?> body) async {
    final res = await _client.post(
      _endpoint,
      headers: {'content-type': 'application/x-amz-json-1.1', 'x-amz-target': 'AWSCognitoIdentityProviderService.$op'},
      body: jsonEncode(body),
    );
    final json = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      final type = (json['__type'] as String? ?? 'Unknown').split('#').last;
      throw AuthException(type);
    }
    return json;
  }

  Future<void> signUp(String email, String password) => _call('SignUp', {
    'ClientId': config.clientId,
    'Username': email,
    'Password': password,
    'UserAttributes': [
      {'Name': 'email', 'Value': email},
    ],
  });

  Future<void> confirm(String email, String code) =>
      _call('ConfirmSignUp', {'ClientId': config.clientId, 'Username': email, 'ConfirmationCode': code});

  Future<void> resendCode(String email) =>
      _call('ResendConfirmationCode', {'ClientId': config.clientId, 'Username': email});

  Future<void> signIn(String email, String password) async {
    final out = await _call('InitiateAuth', {
      'AuthFlow': 'USER_PASSWORD_AUTH',
      'ClientId': config.clientId,
      'AuthParameters': {'USERNAME': email, 'PASSWORD': password},
    });
    _take(out);
  }

  /// Signs in with `google` or `apple` through Cognito's sign-in pages. The
  /// first time, the server joins it to the email account with the same
  /// address; Cognito then turns that first try away once, so it is tried again.
  Future<void> signInWith(String provider) async {
    try {
      await _signInWith(provider);
    } on AuthException catch (e) {
      if (e.type != 'AccountLinked') rethrow;
      await _signInWith(provider);
    }
  }

  Future<void> _signInWith(String provider) async {
    final verifier = _random(48);
    final state = _random(16);
    final url = Uri.https(config.authDomain, '/oauth2/authorize', {
      'response_type': 'code',
      'client_id': config.clientId,
      'redirect_uri': _redirect.toString(),
      'identity_provider': provider == 'apple' ? 'SignInWithApple' : 'Google',
      'scope': 'openid email aws.cognito.signin.user.admin',
      'state': state,
      'code_challenge': base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', ''),
      'code_challenge_method': 'S256',
    });
    final String back;
    try {
      back = await _browser(url, _redirect.scheme);
    } catch (_) {
      throw const AuthException('Cancelled');
    }
    final answer = Uri.parse(back);
    final params = {...answer.queryParameters, ...Uri.splitQueryString(answer.fragment)};
    final error = params['error_description'] ?? params['error'];
    if (error != null) {
      throw AuthException(error.contains('Already found an entry') ? 'AccountLinked' : 'ProviderError');
    }
    final code = params['code'];
    if (code == null || params['state'] != state) throw const AuthException('ProviderError');
    final res = await _client.post(
      Uri.https(config.authDomain, '/oauth2/token'),
      headers: {'content-type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'authorization_code',
        'client_id': config.clientId,
        'code': code,
        'redirect_uri': _redirect.toString(),
        'code_verifier': verifier,
      },
    );
    if (res.statusCode != 200) throw const AuthException('ProviderError');
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    _take({
      'AuthenticationResult': {
        'AccessToken': json['access_token'],
        'RefreshToken': json['refresh_token'],
        'ExpiresIn': json['expires_in'],
      },
    });
  }

  static String _random(int bytes) {
    final r = Random.secure();
    return base64Url.encode(List<int>.generate(bytes, (_) => r.nextInt(256))).replaceAll('=', '');
  }

  /// Signs in again with the refresh token saved last time, so people stay
  /// signed in across restarts. False when there is none or it no longer works.
  ///
  /// An access token saved with more than [_reuseMargin] left is used as is,
  /// with no trip to Cognito: from Korea a new connection to us-east-1 costs
  /// about half a second before the first screen. Should the server turn it
  /// down, the next request refreshes it.
  Future<bool> restore() async {
    final saved = await _store.read();
    if (saved == null) return false;
    _refreshToken = saved;
    if (await _reuseSavedAccess()) return true;
    try {
      await refresh();
      return true;
    } on AuthException {
      await _forget();
      return false;
    } catch (_) {
      // Offline: keep the saved token for next time, but start signed out.
      _refreshToken = null;
      return false;
    }
  }

  static const _reuseMargin = Duration(minutes: 5);

  Future<bool> _reuseSavedAccess() async {
    final saved = await _store.readAccess();
    if (saved == null) return false;
    try {
      final j = jsonDecode(saved) as Map<String, dynamic>;
      final token = j['token'] as String;
      final expiresAt = DateTime.fromMillisecondsSinceEpoch((j['expiresAt'] as num).toInt());
      if (_clock().isAfter(expiresAt.subtract(_reuseMargin))) return false;
      final user = jwtSubject(token);
      _accessToken = token;
      _expiresAt = expiresAt;
      _userId = user;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Ends the session here and revokes the refresh token at Cognito.
  Future<void> signOut() async {
    final refresh = _refreshToken;
    await _forget();
    if (refresh == null) return;
    try {
      await _call('RevokeToken', {'ClientId': config.clientId, 'Token': refresh});
    } catch (_) {
      // Already signed out here; the token expires on its own.
    }
  }

  Future<void> _forget() async {
    _accessToken = _refreshToken = _userId = null;
    _expiresAt = null;
    await _store.delete();
  }

  /// Emails a code for setting a new password.
  Future<void> forgotPassword(String email) =>
      _call('ForgotPassword', {'ClientId': config.clientId, 'Username': email});

  Future<void> resetPassword(String email, String code, String newPassword) => _call('ConfirmForgotPassword', {
    'ClientId': config.clientId,
    'Username': email,
    'ConfirmationCode': code,
    'Password': newPassword,
  });

  /// A valid access token, refreshed a minute before it expires.
  Future<String> accessToken() async {
    final token = _accessToken;
    if (token == null) throw const AuthException('NotSignedIn');
    if (_expiresAt != null && _clock().isAfter(_expiresAt!.subtract(const Duration(minutes: 1)))) {
      await refresh();
    }
    return _accessToken!;
  }

  Future<void> refresh() async {
    final refresh = _refreshToken;
    if (refresh == null) throw const AuthException('NotSignedIn');
    final out = await _call('InitiateAuth', {
      'AuthFlow': 'REFRESH_TOKEN_AUTH',
      'ClientId': config.clientId,
      'AuthParameters': {'REFRESH_TOKEN': refresh},
    });
    _take(out);
  }

  void _take(Map<String, dynamic> out) {
    final result = out['AuthenticationResult'] as Map<String, dynamic>?;
    if (result == null) throw AuthException(out['ChallengeName'] as String? ?? 'Unknown');
    _accessToken = result['AccessToken'] as String;
    _refreshToken = result['RefreshToken'] as String? ?? _refreshToken;
    _expiresAt = _clock().add(Duration(seconds: (result['ExpiresIn'] as num? ?? 3600).toInt()));
    _userId = jwtSubject(_accessToken!);
    final refresh = _refreshToken;
    if (refresh != null && result['RefreshToken'] != null) _store.write(refresh);
    _store.writeAccess(jsonEncode({'token': _accessToken, 'expiresAt': _expiresAt!.millisecondsSinceEpoch}));
  }
}

/// The "sub" claim of a JWT. The token is not verified here; the API does that.
String jwtSubject(String token) {
  final parts = token.split('.');
  if (parts.length != 3) throw const AuthException('BadToken');
  final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
  return (payload as Map<String, dynamic>)['sub'] as String;
}

class AuthException implements Exception {
  const AuthException(this.type);

  /// Cognito's error type, such as `NotAuthorizedException`.
  final String type;

  String get message => switch (type) {
    'UsernameExistsException' => t('이미 가입한 이메일이에요. 로그인해주세요.'),
    'Cancelled' => t('로그인을 취소했어요.'),
    'ProviderError' || 'AccountLinked' => t('로그인하지 못했어요. 다시 시도해주세요.'),
    'NotAuthorizedException' => t('이메일이나 비밀번호가 맞지 않아요.'),
    'UserNotFoundException' => t('이메일이나 비밀번호가 맞지 않아요.'),
    'UserNotConfirmedException' => t('이메일 인증을 마쳐주세요.'),
    'CodeMismatchException' => t('인증 코드가 맞지 않아요.'),
    'ExpiredCodeException' => t('인증 코드가 만료됐어요. 새 코드를 받아주세요.'),
    'InvalidPasswordException' => t('비밀번호는 10자 이상이고 대문자, 소문자, 숫자를 섞어야 해요.'),
    'InvalidParameterException' => t('이메일 형식을 확인해주세요.'),
    'LimitExceededException' || 'TooManyRequestsException' => t('시도가 너무 많아요. 잠시 후 다시 해주세요.'),
    _ => t('로그인 중 문제가 생겼어요. 잠시 후 다시 해주세요.'),
  };

  @override
  String toString() => 'AuthException($type)';
}
