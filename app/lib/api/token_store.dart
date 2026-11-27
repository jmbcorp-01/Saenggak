import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the refresh token is kept between launches.
abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String token);

  /// The last access token and when it expires, so a launch within its hour
  /// needs no trip to Cognito. Never more than the refresh token beside it
  /// can already get.
  Future<String?> readAccess();
  Future<void> writeAccess(String value);

  /// Forgets both.
  Future<void> delete();
}

/// The device keychain (iOS), encrypted storage (Android) or browser storage (web).
class SecureTokenStore implements TokenStore {
  const SecureTokenStore();

  static const _storage = FlutterSecureStorage();
  static const _key = 'refresh_token';
  static const _accessKey = 'access_token';

  @override
  Future<String?> read() async {
    try {
      return await _storage.read(key: _key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String token) async {
    try {
      await _storage.write(key: _key, value: token);
    } catch (_) {
      // Not saved: the person signs in again next launch.
    }
  }

  @override
  Future<String?> readAccess() async {
    try {
      return await _storage.read(key: _accessKey);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeAccess(String value) async {
    try {
      await _storage.write(key: _accessKey, value: value);
    } catch (_) {
      // Not saved: the next launch refreshes instead.
    }
  }

  @override
  Future<void> delete() async {
    try {
      await _storage.delete(key: _key);
      await _storage.delete(key: _accessKey);
    } catch (_) {}
  }
}

/// Keeps the token for this run only. Used in tests and the demo.
class MemoryTokenStore implements TokenStore {
  String? token;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String token) async => this.token = token;

  String? access;

  @override
  Future<String?> readAccess() async => access;

  @override
  Future<void> writeAccess(String value) async => access = value;

  @override
  Future<void> delete() async => token = access = null;
}
