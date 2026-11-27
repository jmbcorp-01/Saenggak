// Records the App Store app preview: real app screens, frame by frame.
// Run: flutter test tool/store_video_test.dart
// Writes build/store/video/<lang>/frame-00001.png ...; tool/store_video.sh joins them.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saenggak/api/demo_backend.dart';
import 'package:saenggak/core/nav.dart';
import 'package:saenggak/data/app_state.dart';
import 'package:saenggak/l10n/l10n.dart';
import 'package:saenggak/main.dart';
import 'package:saenggak/screens/compose_screen.dart';
import 'package:saenggak/theme/tokens.dart';

import 'store_screenshots_test.dart' show drafts, framed, loadFonts, meFor, now, postsFor, searches;

const frame = Duration(microseconds: 33333); // 30 fps

const pastes = {'ko': '어디선가 복사해 온 그럴듯한 긴 문장입니다.', 'en': 'A neat sentence copied from somewhere else.'};

class Recorder {
  Recorder(this.tester, this.dir);
  final WidgetTester tester;
  final String dir;
  int n = 0;

  Future<void> frames(int count) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(frame);
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('shot')));
        final image = await boundary.toImage(pixelRatio: tester.view.devicePixelRatio);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        n++;
        File('$dir/frame-${n.toString().padLeft(5, '0')}.png')
          ..createSync(recursive: true)
          ..writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
  }

  Future<void> seconds(double s) => frames((s * 30).round());
}

void main() {
  setUpAll(loadFonts);

  for (final lang in ['ko', 'en']) {
    testWidgets('preview $lang', (tester) async {
      AppLang.instance.value = lang;
      // iPhone app preview: 886 x 1920.
      tester.view.physicalSize = const Size(886, 1920);
      tester.view.devicePixelRatio = 2.2;
      tester.view.padding = const FakeViewPadding(top: 59 * 2.2, bottom: 34 * 2.2);
      tester.view.viewPadding = const FakeViewPadding(top: 59 * 2.2, bottom: 34 * 2.2);
      addTearDown(tester.view.reset);
      final dir = Directory('build/store/video/$lang');
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      final rec = Recorder(tester, dir.path);

      var clock = now;
      final state = AppState(
        backend: DemoBackend(clock: () => clock, posts: postsFor(lang), me: meFor(lang)),
        clock: () => clock,
      );
      await tester.pumpWidget(framed(SaenggakApp(state: state)));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.text(t('로그인')));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // 1. The feed, scrolling gently.
      await rec.seconds(1.5);
      final feed = tester
          .state<ScrollableState>(
            find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first,
          )
          .position;
      for (var i = 1; i <= 60; i++) {
        final t = i / 60;
        feed.jumpTo(260 * (t * t * (3 - 2 * t)));
        await rec.frames(1);
      }
      await rec.seconds(0.8);
      for (var i = 1; i <= 30; i++) {
        final t = i / 30;
        feed.jumpTo(260 * (1 - t * t * (3 - 2 * t)));
        await rec.frames(1);
      }
      await rec.seconds(0.4);

      // 2. Open the editor.
      final shell = tester.element(find.text(t('추천')).first);
      pushModal<void>(shell, (_) => ComposeScreen(state: state, clock: () => clock));
      await rec.seconds(1.0);

      // 3. Try to paste: it is refused.
      await tester.showKeyboard(find.byKey(const Key('thought')));
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: pastes[lang]!,
          selection: TextSelection.collapsed(offset: pastes[lang]!.length),
        ),
      );
      await rec.seconds(2.2);

      // 4. Type it by hand, a letter at a time.
      final text = drafts[lang]!;
      var typed = '';
      var i = 0;
      for (final ch in text.characters) {
        typed += ch;
        clock = clock.add(Duration(milliseconds: 180 + (i * 97) % 260));
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: typed,
            selection: TextSelection.collapsed(offset: typed.length),
          ),
        );
        await rec.frames(lang == 'ko' ? 3 : 2);
        i++;
      }
      FocusManager.instance.primaryFocus?.unfocus();
      tester.testTextInput.hide();
      await rec.seconds(0.8);

      // 5. Post, and see who thought the same.
      await tester.tap(find.byKey(const Key('submit')));
      await rec.seconds(4.0);
      await tester.tap(find.byTooltip(t('닫기')));
      await rec.seconds(0.8);

      // 6. Search by meaning.
      await tester.tap(find.byIcon(SgIcons.search).first);
      await rec.seconds(0.6);
      final query = searches[lang]!;
      await tester.showKeyboard(find.byKey(const Key('search-input')));
      typed = '';
      for (final ch in query.characters) {
        typed += ch;
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: typed,
            selection: TextSelection.collapsed(offset: typed.length),
          ),
        );
        await rec.frames(5);
      }
      await tester.testTextInput.receiveAction(TextInputAction.search);
      FocusManager.instance.primaryFocus?.unfocus();
      tester.testTextInput.hide();
      await rec.seconds(3.0);
    }, timeout: const Timeout(Duration(minutes: 20)));
  }
}
