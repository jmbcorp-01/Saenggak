import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// Server settings. Mobile builds get them at build time:
///   flutter run --dart-define=API_URL=https://... \
///     --dart-define=COGNITO_REGION=us-east-1 --dart-define=COGNITO_CLIENT_ID=...
/// The deployed web app reads them from config.json next to index.html, which
/// the deploy writes from the stack outputs. Without either, the app runs on
/// the offline demo backend.
class ApiConfig {
  const ApiConfig({
    required this.apiUrl,
    required this.region,
    required this.clientId,
    this.authDomain = '',
    this.signInWith = const [],
    this.firebase,
  });

  static const _signInWith = String.fromEnvironment('SIGN_IN_WITH');

  static final fromEnvironment = ApiConfig(
    apiUrl: const String.fromEnvironment('API_URL'),
    region: const String.fromEnvironment('COGNITO_REGION', defaultValue: 'us-east-1'),
    clientId: const String.fromEnvironment('COGNITO_CLIENT_ID'),
    authDomain: const String.fromEnvironment('AUTH_DOMAIN'),
    signInWith: _signInWith.isEmpty ? const [] : _signInWith.split(','),
  );

  factory ApiConfig.fromJson(Map<String, dynamic> j) => ApiConfig(
    apiUrl: j['apiUrl'] as String? ?? '',
    region: j['cognitoRegion'] as String? ?? 'us-east-1',
    clientId: j['cognitoClientId'] as String? ?? '',
    authDomain: j['authDomain'] as String? ?? '',
    signInWith: [for (final p in j['signInWith'] as List? ?? const []) p as String],
    firebase: j['firebase'],
  );

  /// Build-time settings first; on the web, config.json when there are none.
  static Future<ApiConfig> load({http.Client? client, bool web = kIsWeb}) async {
    if (!fromEnvironment.isDemo || !web) return fromEnvironment;
    try {
      final res = await (client ?? http.Client())
          .get(Uri.base.resolve('config.json'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return fromEnvironment;
      return ApiConfig.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
    } catch (_) {
      return fromEnvironment;
    }
  }

  final String apiUrl;
  final String region;
  final String clientId;

  /// Cognito's sign-in pages, such as auth.saenggak.app. Empty until set up.
  final String authDomain;

  /// The other ways in that are set up: `google`, `apple`.
  final List<String> signInWith;

  /// The web app's Firebase settings for push alerts, as config.json has them.
  final Object? firebase;

  /// The ways in the app can offer: set up on the server and in this build.
  List<String> get socialProviders => authDomain.isEmpty ? const [] : signInWith;

  bool get isDemo => apiUrl.isEmpty || clientId.isEmpty;
}
