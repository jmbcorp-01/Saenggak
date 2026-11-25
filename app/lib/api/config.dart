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
  const ApiConfig({required this.apiUrl, required this.region, required this.clientId});

  static const fromEnvironment = ApiConfig(
    apiUrl: String.fromEnvironment('API_URL'),
    region: String.fromEnvironment('COGNITO_REGION', defaultValue: 'us-east-1'),
    clientId: String.fromEnvironment('COGNITO_CLIENT_ID'),
  );

  factory ApiConfig.fromJson(Map<String, dynamic> j) => ApiConfig(
    apiUrl: j['apiUrl'] as String? ?? '',
    region: j['cognitoRegion'] as String? ?? 'us-east-1',
    clientId: j['cognitoClientId'] as String? ?? '',
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

  bool get isDemo => apiUrl.isEmpty || clientId.isEmpty;
}
