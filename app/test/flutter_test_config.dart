import 'dart:async';

import 'package:saenggak/l10n/l10n.dart';

/// The tests read the Korean text, so they run in Korean whatever the
/// machine's language is.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AppLang.instance.value = 'ko';
  await testMain();
}
