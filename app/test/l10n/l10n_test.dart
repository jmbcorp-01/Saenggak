import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saenggak/api/demo_backend.dart';
import 'package:saenggak/data/app_state.dart';
import 'package:saenggak/l10n/en.dart';
import 'package:saenggak/l10n/l10n.dart';
import 'package:saenggak/main.dart';
import 'package:saenggak/models/social.dart';

void main() {
  tearDown(() => AppLang.instance.value = 'ko');

  test('Korean text is used as is, and arguments fill the blanks', () {
    expect(t('{0}분', [5]), '5분');
    AppLang.instance.value = 'en';
    expect(t('{0}분', [5]), '5m');
    expect(t('{0}에서 번역됨 · ', ['Korean']), 'Translated from Korean · ');
  });

  test('English picks the singular when the first number is 1', () {
    AppLang.instance.value = 'en';
    expect(t('새 생각 {0}개', [1]), '1 new thought');
    expect(t('새 생각 {0}개', [3]), '3 new thoughts');
  });

  test('every Korean string in the app has an English version', () {
    final call = RegExp(r"(?<![A-Za-z0-9_])t\('((?:[^'\\]|\\.)*)'");
    final missing = <String>{};
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      for (final m in call.allMatches(file.readAsStringSync())) {
        final key = m[1]!.replaceAll(r'\n', '\n').replaceAll(r"\'", "'");
        if (!english.containsKey(key)) missing.add('${file.path}: $key');
      }
    }
    for (final reason in reportReasons.values) {
      if (!english.containsKey(reason)) missing.add('report reason: $reason');
    }
    expect(missing, isEmpty);
  });

  testWidgets('English on the start screen switches the app at once', (tester) async {
    await tester.pumpWidget(SaenggakApp(state: AppState(backend: DemoBackend())));
    expect(find.text('계정 만들기'), findsOneWidget);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    await tester.tap(find.text('한국어'));
    await tester.pumpAndSettle();
    expect(find.text('계정 만들기'), findsOneWidget);
  });
}
