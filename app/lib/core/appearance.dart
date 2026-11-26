import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:material_ui/material_ui.dart';

/// Light, dark, or whatever the device uses. Kept on the device between
/// launches; the server does not need it.
class Appearance extends ValueNotifier<ThemeMode> {
  Appearance._() : super(ThemeMode.system);

  static final instance = Appearance._();

  static const _storage = FlutterSecureStorage();
  static const _key = 'theme_mode';

  /// Reads the saved choice. Leaves the default if storage is unavailable.
  Future<void> load() async {
    try {
      final saved = await _storage.read(key: _key);
      value = ThemeMode.values.firstWhere((m) => m.name == saved, orElse: () => ThemeMode.system);
    } catch (_) {}
  }

  Future<void> set(ThemeMode mode) async {
    value = mode;
    try {
      await _storage.write(key: _key, value: mode.name);
    } catch (_) {}
  }
}
