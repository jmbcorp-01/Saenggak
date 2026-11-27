import 'dart:async';

import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Push alerts outside the app, through Firebase Cloud Messaging. Without
/// Firebase settings in the build (or in config.json on the web) there is no
/// push, and everything else works as before.
///
/// The settings are public identifiers, not secrets: mobile builds take them
/// from config/production.json, the web app from the `firebase` part of
/// config.json, which the deploy writes from the same file.
class FirebaseSettings {
  const FirebaseSettings({
    required this.projectId,
    required this.senderId,
    required this.apiKey,
    required this.appId,
    this.vapidKey = '',
  });

  /// From the build, for this platform.
  static FirebaseSettings? fromEnvironment() {
    const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
    const senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
    final (apiKey, appId) = switch (defaultTargetPlatform) {
      TargetPlatform.iOS => (
        const String.fromEnvironment('FIREBASE_IOS_API_KEY'),
        const String.fromEnvironment('FIREBASE_IOS_APP_ID'),
      ),
      _ => (
        const String.fromEnvironment('FIREBASE_ANDROID_API_KEY'),
        const String.fromEnvironment('FIREBASE_ANDROID_APP_ID'),
      ),
    };
    final s = FirebaseSettings(projectId: projectId, senderId: senderId, apiKey: apiKey, appId: appId);
    return s.complete ? s : null;
  }

  /// The `firebase` part of the web app's config.json.
  static FirebaseSettings? fromJson(Object? j) {
    if (j is! Map) return null;
    final s = FirebaseSettings(
      projectId: j['projectId'] as String? ?? '',
      senderId: j['messagingSenderId'] as String? ?? '',
      apiKey: j['apiKey'] as String? ?? '',
      appId: j['appId'] as String? ?? '',
      vapidKey: j['vapidKey'] as String? ?? '',
    );
    return s.complete && s.vapidKey.isNotEmpty ? s : null;
  }

  final String projectId;
  final String senderId;
  final String apiKey;
  final String appId;

  /// The web push key pair's public half (Firebase > Cloud Messaging > Web Push certificates).
  final String vapidKey;

  bool get complete => projectId.isNotEmpty && senderId.isNotEmpty && apiKey.isNotEmpty && appId.isNotEmpty;

  FirebaseOptions get options => FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: senderId,
    projectId: projectId,
    authDomain: kIsWeb ? '$projectId.firebaseapp.com' : null,
  );
}

/// Whether the person let the app show alerts.
enum PushPermission { granted, denied, notAsked, unsupported }

/// What a tapped alert asks to open.
class PushTap {
  const PushTap({required this.kind, this.postId, this.userId});

  factory PushTap.fromData(Map<String, dynamic> d) =>
      PushTap(kind: '${d['kind'] ?? ''}', postId: d['postId'] as String?, userId: d['userId'] as String?);

  /// empathy, follow or post.
  final String kind;
  final String? postId;
  final String? userId;
}

/// The device side of push: permission, the token, and alerts arriving or tapped.
abstract class PushService {
  /// ios, android or web.
  String get platform;
  Future<PushPermission> permission();

  /// Asks the person. On the web this must follow a tap.
  Future<PushPermission> request();
  Future<String?> token();
  Stream<String> get tokenRefresh;

  /// An alert that arrived while the app was open. The app refreshes its
  /// notifications instead of showing a banner over itself.
  Stream<void> get foreground;

  /// An alert the person tapped while the app was in the background.
  Stream<PushTap> get taps;

  /// The alert that opened the app from closed, once.
  Future<PushTap?> launchTap();

  /// The number on the app icon. Alerts set it while the app is away; the
  /// app puts it right once the person has read them.
  Future<void> setBadge(int count);
}

class FirebasePushService implements PushService {
  FirebasePushService._(this._vapidKey);

  final String _vapidKey;
  FirebaseMessaging get _m => FirebaseMessaging.instance;

  /// Starts Firebase, or returns null when it is not set up or fails to start.
  static Future<FirebasePushService?> start(FirebaseSettings? settings) async {
    if (settings == null) return null;
    try {
      await Firebase.initializeApp(options: settings.options);
      if (kIsWeb && !await FirebaseMessaging.instance.isSupported()) return null;
      return FirebasePushService._(settings.vapidKey);
    } catch (e) {
      debugPrint('push unavailable: $e');
      return null;
    }
  }

  @override
  String get platform => kIsWeb
      ? 'web'
      : defaultTargetPlatform == TargetPlatform.iOS
      ? 'ios'
      : 'android';

  static PushPermission _of(AuthorizationStatus s) => switch (s) {
    AuthorizationStatus.authorized || AuthorizationStatus.provisional => PushPermission.granted,
    AuthorizationStatus.denied || AuthorizationStatus.deniedPermanently => PushPermission.denied,
    AuthorizationStatus.notDetermined => PushPermission.notAsked,
  };

  @override
  Future<PushPermission> permission() async {
    try {
      return _of((await _m.getNotificationSettings()).authorizationStatus);
    } catch (_) {
      return PushPermission.unsupported;
    }
  }

  @override
  Future<PushPermission> request() async {
    try {
      return _of((await _m.requestPermission()).authorizationStatus);
    } catch (_) {
      return PushPermission.unsupported;
    }
  }

  @override
  Future<String?> token() async {
    try {
      // The registration token, which the server sends to through FCM v1. The
      // newer register()/onRegistered pair gives installation ids instead.
      // ignore: deprecated_member_use
      return await _m.getToken(vapidKey: kIsWeb ? _vapidKey : null);
    } catch (e) {
      debugPrint('push token unavailable: $e');
      return null;
    }
  }

  @override
  // ignore: deprecated_member_use
  Stream<String> get tokenRefresh => _m.onTokenRefresh;

  @override
  Stream<void> get foreground => FirebaseMessaging.onMessage.map((_) {});

  @override
  Stream<PushTap> get taps => FirebaseMessaging.onMessageOpenedApp.map((m) => PushTap.fromData(m.data));

  @override
  Future<void> setBadge(int count) async {
    // Android launchers count the alerts in the tray themselves, and clear
    // them with it; only iPhones keep a number the app has to reset.
    if (platform != 'ios') return;
    try {
      await AppBadgePlus.updateBadge(count);
    } catch (_) {}
  }

  @override
  Future<PushTap?> launchTap() async {
    try {
      final m = await _m.getInitialMessage();
      return m == null ? null : PushTap.fromData(m.data);
    } catch (_) {
      return null;
    }
  }
}
