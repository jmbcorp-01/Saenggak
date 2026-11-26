import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The store builds take their server settings from this file.
void main() {
  final config = jsonDecode(File('config/production.json').readAsStringSync()) as Map<String, dynamic>;

  test('store builds call the API through CloudFront, which the API requires', () {
    final api = Uri.parse(config['API_URL'] as String);
    expect(api.scheme, 'https');
    expect(api.host, isNot(contains('execute-api')));
    expect(api.path, '/api');
  });

  test('store builds have sign-in and site settings', () {
    expect(config['COGNITO_CLIENT_ID'], isNotEmpty);
    expect(Uri.parse(config['SITE_URL'] as String).scheme, 'https');
  });
}
