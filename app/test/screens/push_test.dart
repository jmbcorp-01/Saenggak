import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saenggak/api/config.dart';
import 'package:saenggak/api/demo_backend.dart';
import 'package:saenggak/core/push.dart';
import 'package:saenggak/data/app_state.dart';
import 'package:saenggak/main.dart';
import 'package:saenggak/models/growth.dart';
import 'package:saenggak/screens/post_screen.dart';
import 'package:saenggak/screens/settings_screen.dart';

class FakePush implements PushService {
  FakePush({this.platform = 'ios', this.state = PushPermission.notAsked, this.launch});

  @override
  final String platform;
  PushPermission state;
  PushTap? launch;
  int asked = 0;
  final _taps = StreamController<PushTap>.broadcast();
  final _foreground = StreamController<void>.broadcast();
  final _refresh = StreamController<String>.broadcast();

  @override
  Future<PushPermission> permission() async => state;

  @override
  Future<PushPermission> request() async {
    asked++;
    return state = PushPermission.granted;
  }

  @override
  Future<String?> token() async => 'device-token-$platform';

  @override
  Stream<String> get tokenRefresh => _refresh.stream;

  @override
  Stream<void> get foreground => _foreground.stream;

  @override
  Stream<PushTap> get taps => _taps.stream;

  @override
  Future<PushTap?> launchTap() async {
    final t = launch;
    launch = null;
    return t;
  }

  final badges = <int>[];

  @override
  Future<void> setBadge(int count) async => badges.add(count);

  void tap(PushTap t) => _taps.add(t);
  void refresh(String token) => _refresh.add(token);
}

Future<(AppState, DemoBackend)> openHome(WidgetTester tester, FakePush push) async {
  final backend = DemoBackend();
  final state = AppState(backend: backend)..pushReady = Future.value(push);
  await tester.pumpWidget(SaenggakApp(state: state));
  await tester.tap(find.text('로그인'));
  await tester.pumpAndSettle();
  return (state, backend);
}

void main() {
  testWidgets('a phone asks once and registers its device', (tester) async {
    final push = FakePush();
    final (state, backend) = await openHome(tester, push);
    expect(push.asked, 1);
    expect(state.pushPermission, PushPermission.granted);
    expect(backend.pushTokens, {'device-token-ios': 'ios'});
  });

  test('a new token is registered, and sign-out lets go of the device', () async {
    final push = FakePush(state: PushPermission.granted);
    final backend = DemoBackend();
    final state = AppState(backend: backend)..pushReady = Future.value(push);
    await state.start();
    await state.startPush();
    push.refresh('device-token-new');
    await Future<void>.delayed(Duration.zero);
    expect(backend.pushTokens['device-token-new'], 'ios');
    await state.signOut();
    expect(backend.pushTokens.containsKey('device-token-new'), isFalse);
  });

  testWidgets('the web waits for a tap in the notifications tab', (tester) async {
    final push = FakePush(platform: 'web');
    final (_, backend) = await openHome(tester, push);
    expect(push.asked, 0);
    expect(backend.pushTokens, isEmpty);

    await tester.tap(find.byTooltip('알림').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('push-banner')), findsOneWidget);
    await tester.tap(find.byKey(const Key('push-enable')));
    await tester.pumpAndSettle();
    expect(push.asked, 1);
    expect(backend.pushTokens, {'device-token-web': 'web'});
    expect(find.byKey(const Key('push-banner')), findsNothing);
  });

  testWidgets('a blocked device is told where to allow alerts', (tester) async {
    final push = FakePush(platform: 'web', state: PushPermission.denied);
    await openHome(tester, push);
    await tester.tap(find.byTooltip('알림').first);
    await tester.pumpAndSettle();
    expect(find.text('알림이 막혀 있어요. 기기나 브라우저 설정에서 생각의 알림을 허용해 주세요.'), findsOneWidget);
    expect(find.byKey(const Key('push-enable')), findsNothing);
  });

  testWidgets('a tapped alert opens its post, or the notifications', (tester) async {
    final push = FakePush(state: PushPermission.granted);
    final (state, _) = await openHome(tester, push);
    push.tap(PushTap(kind: 'empathy', postId: state.feed.first.id));
    await tester.pumpAndSettle();
    expect(find.byType(PostScreen), findsOneWidget);
  });

  testWidgets('the alert that opened the app is followed once home is up', (tester) async {
    final push = FakePush(
      state: PushPermission.granted,
      launch: const PushTap(kind: 'follow'),
    );
    final (state, _) = await openHome(tester, push);
    await tester.pumpAndSettle();
    expect(find.text('아직 알림이 없어요.'), findsOneWidget);
    expect(state.unreadNotifications, 0);
  });

  testWidgets('the icon number follows the unread count, and clears once read', (tester) async {
    final push = FakePush(state: PushPermission.granted);
    final (state, _) = await openHome(tester, push);
    expect(push.badges.last, state.unreadNotifications);
    await tester.tap(find.byTooltip('알림').first);
    await tester.pumpAndSettle();
    expect(push.badges.last, 0);
  });

  testWidgets('alerts allowed in the device settings count once the app is back', (tester) async {
    final push = FakePush(state: PushPermission.denied);
    final (state, backend) = await openHome(tester, push);
    expect(backend.pushTokens, isEmpty);
    push.state = PushPermission.granted;
    for (final s in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pumpAndSettle();
    expect(state.pushPermission, PushPermission.granted);
    expect(backend.pushTokens, {'device-token-ios': 'ios'});
  });

  testWidgets('settings turn each kind of alert off', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = DemoBackend();
    final state = AppState(backend: backend)..pushReady = Future.value(FakePush(state: PushPermission.granted));
    await state.start();
    await state.startPush();
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(state: state)));
    await tester.pumpAndSettle();
    expect(find.text('이 기기에서 알림을 받고 있어요'), findsOneWidget);
    await tester.tap(find.byKey(const Key('push-empathy')));
    await tester.pumpAndSettle();
    final saved = await backend.pushSettings();
    expect(saved.empathy, isFalse);
    expect(saved.follow, isTrue);
  });

  testWidgets('without Firebase there is no push section at all', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = AppState(backend: DemoBackend());
    await state.start();
    await state.startPush(ask: true);
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(state: state)));
    await tester.pumpAndSettle();
    expect(find.text('푸시 알림'), findsNothing);
  });

  test('Firebase settings need every part, and the web needs its push key', () {
    expect(FirebaseSettings.fromJson(null), isNull);
    final web = {'projectId': 'p', 'messagingSenderId': '1', 'apiKey': 'k', 'appId': 'a'};
    expect(FirebaseSettings.fromJson(web), isNull);
    expect(FirebaseSettings.fromJson({...web, 'vapidKey': 'v'})!.options.projectId, 'p');
    expect(FirebaseSettings.fromEnvironment(), isNull);
    expect(ApiConfig.fromJson({'apiUrl': 'x', 'firebase': web}).firebase, web);
  });

  test('push settings round-trip', () {
    const s = PushSettings(empathy: false);
    expect(PushSettings.fromJson(s.toJson()).empathy, isFalse);
    expect(PushSettings.fromJson(const {}).posts, isTrue);
  });
}
