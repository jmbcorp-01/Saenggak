// Renders the raw app screens for the App Store and Google Play listings.
// Run: flutter test tool/store_screenshots_test.dart
// Writes build/store/raw/<lang>-<device>-<n>-<name>.png; tool/store_frames.py
// then adds the captions and background.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saenggak/api/demo_backend.dart';
import 'package:saenggak/core/nav.dart';
import 'package:saenggak/data/app_state.dart';
import 'package:saenggak/l10n/l10n.dart';
import 'package:saenggak/main.dart';
import 'package:saenggak/models/post.dart';
import 'package:saenggak/models/profile.dart';
import 'package:saenggak/screens/compose_screen.dart';
import 'package:saenggak/theme/tokens.dart';

import '../test/helpers.dart';

class Device {
  const Device(this.name, this.size, this.ratio, this.top, this.bottom);
  final String name;
  final Size size; // physical pixels
  final double ratio;
  final double top; // logical safe-area insets
  final double bottom;
}

const devices = [
  Device('iphone', Size(1290, 2796), 3, 59, 34),
  Device('ipad', Size(2064, 2752), 2.4, 24, 20),
  Device('android', Size(1080, 1920), 2.625, 24, 0),
];

final now = DateTime(2026, 11, 26, 21, 40);

Post _post(
  String id,
  String name,
  String handle,
  String body,
  String lang,
  int minutesAgo,
  Duration typing,
  int empathy, {
  String? translation,
  bool mine = false,
  bool empathized = false,
}) => Post(
  id: id,
  authorId: 'u-$handle',
  authorName: name,
  authorHandle: handle,
  body: body,
  lang: lang,
  translation: translation,
  createdAt: now.subtract(Duration(minutes: minutesAgo)),
  typingTime: typing,
  empathyCount: empathy,
  empathizedByMe: empathized,
  isMine: mine,
);

List<Post> postsFor(String lang) => lang == 'ko'
    ? [
        _post(
          'p1',
          '서하',
          'seoha',
          '오늘은 아무 말도 하지 않은 시간이 가장 길었다. 그런데 이상하게 그 시간에 나를 가장 많이 들은 것 같다.',
          'ko',
          38,
          const Duration(minutes: 2, seconds: 18),
          24,
        ),
        _post(
          'p2',
          'Daniel',
          'daniel.k',
          "We don't move because we are sure. We become sure after we move.",
          'en',
          95,
          const Duration(minutes: 1, seconds: 5),
          9,
          translation: '우리는 확신이 있어서 움직이는 게 아니라, 움직이고 나서야 확신을 만든다고 생각한다.',
          empathized: true,
        ),
        _post(
          'p3',
          '민지',
          'minji',
          '퇴근길에 붕어빵을 샀다. 봉투가 따뜻해서 집에 오는 내내 손을 넣고 걸었다. 겨울은 원래 이런 맛이었지.',
          'ko',
          160,
          const Duration(minutes: 1, seconds: 52),
          37,
        ),
        _post(
          'p4',
          '하루',
          'haru',
          '지하철에서 모르는 사람이 내 어깨에 기대 잠들었다. 깨우지 않았다. 나도 그렇게 기대고 싶었던 날이 있었으니까.',
          'ko',
          300,
          const Duration(minutes: 3, seconds: 41),
          51,
        ),
        _post(
          'p5',
          '도윤',
          'doyun',
          '오래된 친구에게 먼저 연락했다. 별일 없냐는 한마디에 한 시간을 웃었다. 미루던 건 용기가 아니라 핑계였다.',
          'ko',
          420,
          const Duration(minutes: 2, seconds: 49),
          18,
        ),
        _post(
          'm1',
          '윤서',
          'yoonseo',
          '창문을 열어두고 잤더니 새벽에 빗소리에 깼다. 다시 잠들지 않고 그냥 들었다.',
          'ko',
          1500,
          const Duration(minutes: 1, seconds: 34),
          12,
          mine: true,
        ),
        _post(
          'm2',
          '윤서',
          'yoonseo',
          '좋아하는 노래를 처음 들었던 날을 기억한다. 그날의 날씨까지 같이 떠오른다.',
          'ko',
          2950,
          const Duration(minutes: 1, seconds: 12),
          7,
          mine: true,
        ),
      ]
    : [
        _post(
          'p1',
          'Seoha',
          'seoha',
          '오늘은 아무 말도 하지 않은 시간이 가장 길었다. 그런데 이상하게 그 시간에 나를 가장 많이 들은 것 같다.',
          'ko',
          38,
          const Duration(minutes: 2, seconds: 18),
          24,
          translation: 'Today the longest stretch was the time I said nothing. Strangely, that was when I listened to myself the most.',
        ),
        _post(
          'p2',
          'Daniel',
          'daniel.k',
          "We don't move because we are sure. We become sure after we move.",
          'en',
          95,
          const Duration(minutes: 1, seconds: 5),
          9,
          empathized: true,
        ),
        _post(
          'p3',
          'Emma',
          'emma.r',
          'I left my phone in another room tonight. The evening felt twice as long, and I mean that in the best way.',
          'en',
          160,
          const Duration(minutes: 1, seconds: 52),
          37,
        ),
        _post(
          'p4',
          'Haru',
          'haru',
          '지하철에서 모르는 사람이 내 어깨에 기대 잠들었다. 깨우지 않았다. 나도 그렇게 기대고 싶었던 날이 있었으니까.',
          'ko',
          300,
          const Duration(minutes: 3, seconds: 41),
          51,
          translation: "A stranger fell asleep on my shoulder on the subway. I didn't wake them. There was a day I wanted to lean on someone like that too.",
        ),
        _post(
          'p5',
          'Noah',
          'noah',
          'I called an old friend first. One "how have you been" turned into an hour of laughing. It was never courage I lacked, only excuses.',
          'en',
          420,
          const Duration(minutes: 2, seconds: 49),
          18,
        ),
        _post(
          'm1',
          'Yoonseo',
          'yoonseo',
          "I left the window open and woke to rain before dawn. I didn't go back to sleep. I just listened.",
          'en',
          1500,
          const Duration(minutes: 1, seconds: 34),
          12,
          mine: true,
        ),
        _post(
          'm2',
          'Yoonseo',
          'yoonseo',
          'I remember the day I first heard my favorite song. The weather of that day comes back with it.',
          'en',
          2950,
          const Duration(minutes: 1, seconds: 12),
          7,
          mine: true,
        ),
      ];

Profile meFor(String lang) => Profile(
  id: 'me',
  handle: 'yoonseo',
  displayName: lang == 'ko' ? '윤서' : 'Yoonseo',
  bio: lang == 'ko' ? '조용한 날에 생각을 씁니다.' : 'I write on quiet days.',
  locale: lang,
  writingDays: 23,
  followUnlocked: true,
  followers: 41,
  following: 28,
  isMe: true,
);

const drafts = {
  'ko': '비가 오면 약속을 미루고 싶어진다. 사실 비 때문이 아니라, 미룰 핑계가 필요했던 것 같다. 오늘은 그냥 나가 보기로 했다.',
  'en': "When it rains I want to put off every plan. Maybe it was never the rain, just an excuse I needed. Today I'm going anyway.",
};
const searches = {'ko': '핑계', 'en': 'excuse'};

Future<void> loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
    }
    await loader.load();
  }

  await family(SgFonts.sans, [
    'assets/fonts/NotoSansKR-Regular.ttf',
    'assets/fonts/NotoSansKR-Medium.ttf',
    'assets/fonts/NotoSansKR-Bold.ttf',
  ]);
  await family(SgFonts.mono, ['assets/fonts/IBMPlexMono-Regular.ttf', 'assets/fonts/IBMPlexMono-Medium.ttf']);
  final sdk = Platform.environment['FLUTTER_ROOT'] ?? '/home/claude/sdk/flutter';
  await family('MaterialIcons', ['$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
}

Future<void> shoot(WidgetTester tester, String path) async {
  await tester.pump(const Duration(milliseconds: 50));
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('shot')));
    final image = await boundary.toImage(pixelRatio: tester.view.devicePixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Widget framed(Widget app) => RepaintBoundary(key: const Key('shot'), child: app);

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(loadFonts);

  for (final lang in ['ko', 'en']) {
    for (final d in devices) {
      testWidgets('$lang $d', (tester) async {
        AppLang.instance.value = lang;
        tester.view.physicalSize = d.size;
        tester.view.devicePixelRatio = d.ratio;
        tester.view.padding = FakeViewPadding(top: d.top * d.ratio, bottom: d.bottom * d.ratio);
        tester.view.viewPadding = FakeViewPadding(top: d.top * d.ratio, bottom: d.bottom * d.ratio);
        addTearDown(tester.view.reset);
        final out = 'build/store/raw/$lang-${d.name}';

        var clock = now;
        final state = AppState(
          backend: DemoBackend(clock: () => clock, posts: postsFor(lang), me: meFor(lang)),
          clock: () => clock,
        );

        // 1. Start screen.
        await tester.pumpWidget(framed(SaenggakApp(state: state)));
        await settle(tester);
        await shoot(tester, '$out-1-start.png');

        // 2. Feed.
        await tester.tap(find.text(t('로그인')));
        await settle(tester);
        await shoot(tester, '$out-2-feed.png');

        // 3. Writing, part way through.
        final shell = tester.element(find.text(t('추천')).first);
        pushModal<void>(shell, (_) => ComposeScreen(state: state, clock: () => clock));
        await settle(tester);
        await tester.showKeyboard(find.byKey(const Key('thought')));
        final text = drafts[lang]!;
        final cut = text.characters.length * 2 ~/ 3;
        await typeLikeAPerson(tester, text.characters.take(cut).toString(), (g) => clock = clock.add(g));
        tester.testTextInput.hide();
        FocusManager.instance.primaryFocus?.unfocus();
        await settle(tester);
        await shoot(tester, '$out-3-compose.png');

        // 4. The result after posting.
        await tester.showKeyboard(find.byKey(const Key('thought')));
        await typeLikeAPerson(
          tester,
          text.characters.skip(cut).toString(),
          (g) => clock = clock.add(g),
          start: text.characters.take(cut).toString(),
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        await tester.tap(find.byKey(const Key('submit')));
        await settle(tester);
        await shoot(tester, '$out-4-result.png');
        Navigator.of(tester.element(find.byType(Scaffold).last))
            .popUntil((r) => r.isFirst || r.settings.name == '/home');
        await settle(tester);

        // 5. Search by meaning.
        await tester.tap(find.byIcon(SgIcons.search).first);
        await settle(tester);
        await tester.enterText(find.byKey(const Key('search-input')), searches[lang]!);
        await tester.testTextInput.receiveAction(TextInputAction.search);
        FocusManager.instance.primaryFocus?.unfocus();
        await settle(tester);
        await shoot(tester, '$out-5-search.png');

        // 6. Own profile.
        await tester.tap(find.byIcon(SgIcons.person).first);
        await settle(tester);
        await shoot(tester, '$out-6-profile.png');
      });
    }
  }
}
