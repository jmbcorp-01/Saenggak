import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:material_ui/material_ui.dart';

import 'en.dart';

/// The languages the app is written in.
const supportedLangs = ['ko', 'en'];

/// The language the app speaks: Korean when the device is set to Korean,
/// English everywhere else, unless the person picked one. The pick is kept on
/// the device, and on the account once they are signed in.
class AppLang extends ValueNotifier<String> {
  AppLang._() : super(deviceLang());

  static final instance = AppLang._();

  static const _storage = FlutterSecureStorage();
  static const _key = 'app_lang';

  /// Whether the person chose a language, rather than following the device.
  bool chosen = false;

  /// The device's (or, on iOS and Android, this app's) preferred language,
  /// reduced to the ones the app has.
  static String deviceLang() {
    final locales = PlatformDispatcher.instance.locales;
    final first = locales.isEmpty ? 'en' : locales.first.languageCode;
    return first == 'ko' ? 'ko' : 'en';
  }

  /// Reads the saved choice. Leaves the device language if there is none.
  Future<void> load() async {
    try {
      final saved = await _storage.read(key: _key);
      if (supportedLangs.contains(saved)) {
        value = saved!;
        chosen = true;
      }
    } catch (_) {}
  }

  /// The device language changed; follow it unless the person chose one.
  void deviceChanged() {
    if (!chosen) value = deviceLang();
  }

  /// Switches at once; saving to the device happens in the background.
  void set(String lang) {
    if (!supportedLangs.contains(lang)) return;
    value = lang;
    chosen = true;
    _storage.write(key: _key, value: lang).catchError((_) {});
  }
}

/// Translates a Korean source string into the app's language.
///
/// Arguments fill `{0}`, `{1}`… in order. An English entry written as
/// `'one|other'` picks `one` when the first argument is 1.
String t(String ko, [List<Object?> args = const []]) {
  var s = ko;
  if (AppLang.instance.value == 'en') {
    final en = english[ko];
    if (en != null) {
      final bar = en.indexOf('|');
      s = bar < 0
          ? en
          : (args.isNotEmpty && args.first.toString() == '1' ? en.substring(0, bar) : en.substring(bar + 1));
    }
  }
  for (var i = 0; i < args.length; i++) {
    s = s.replaceAll('{$i}', '${args[i]}');
  }
  return s;
}
