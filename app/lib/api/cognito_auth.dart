import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';

/// Email sign-up and sign-in with Amazon Cognito, called directly over HTTPS.
/// These Cognito operations are public, so no AWS signing is needed.
class CognitoAuth {
  CognitoAuth(this.config, {http.Client? client, DateTime Function()? clock})
    : _client = client ?? http.Client(),
      _clock = clock ?? DateTime.now;

  final ApiConfig config;
  final http.Client _client;
  final DateTime Function() _clock;

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

  void signOut() {
    _accessToken = _refreshToken = _userId = null;
    _expiresAt = null;
  }

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
    'UsernameExistsException' => '이미 가입한 이메일이에요. 로그인해주세요.',
    'NotAuthorizedException' => '이메일이나 비밀번호가 맞지 않아요.',
    'UserNotFoundException' => '이메일이나 비밀번호가 맞지 않아요.',
    'UserNotConfirmedException' => '이메일 인증을 마쳐주세요.',
    'CodeMismatchException' => '인증 코드가 맞지 않아요.',
    'ExpiredCodeException' => '인증 코드가 만료됐어요. 새 코드를 받아주세요.',
    'InvalidPasswordException' => '비밀번호는 10자 이상이고 대문자, 소문자, 숫자를 섞어야 해요.',
    'InvalidParameterException' => '이메일 형식을 확인해주세요.',
    'LimitExceededException' || 'TooManyRequestsException' => '시도가 너무 많아요. 잠시 후 다시 해주세요.',
    _ => '로그인 중 문제가 생겼어요. 잠시 후 다시 해주세요.',
  };

  @override
  String toString() => 'AuthException($type)';
}
