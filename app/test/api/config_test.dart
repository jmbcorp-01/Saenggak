import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saenggak/api/config.dart';

void main() {
  test('the web app reads the deployed settings from config.json', () async {
    final client = MockClient((req) async {
      expect(req.url.path, endsWith('config.json'));
      return http.Response(
        jsonEncode({'apiUrl': 'https://api.example', 'cognitoRegion': 'ap-northeast-2', 'cognitoClientId': 'abc'}),
        200,
      );
    });
    final config = await ApiConfig.load(client: client, web: true);
    expect(config.isDemo, isFalse);
    expect(config.apiUrl, 'https://api.example');
    expect(config.region, 'ap-northeast-2');
  });

  test('falls back to the demo when config.json is missing', () async {
    final client = MockClient((_) async => http.Response('not found', 404));
    expect((await ApiConfig.load(client: client, web: true)).isDemo, isTrue);
  });

  test('mobile builds never fetch config.json', () async {
    final client = MockClient((_) async => fail('should not fetch'));
    expect((await ApiConfig.load(client: client, web: false)).isDemo, isTrue);
  });
}
