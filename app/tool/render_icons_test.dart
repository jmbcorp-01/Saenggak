// Renders the app icon and splash images from the symbol mark.
// Run: flutter test tool/render_icons_test.dart
// Then: dart run flutter_launcher_icons && dart run flutter_native_splash:create
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saenggak/theme/tokens.dart';
import 'package:saenggak/widgets/symbol_mark.dart';

Future<void> render(WidgetTester tester, String path, {required double markShare, Color? background}) async {
  const side = 1024.0;
  final key = GlobalKey();
  await tester.pumpWidget(
    Center(
      child: RepaintBoundary(
        key: key,
        child: Container(
          width: side,
          height: side,
          color: background ?? const Color(0x00000000),
          alignment: Alignment.center,
          child: SymbolMark(size: side * markShare, semanticLabel: null),
        ),
      ),
    ),
  );
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('render icons', (tester) async {
    tester.view.physicalSize = const Size(1024, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Full icon (iOS, web, legacy Android): the mark on the warm paper colour.
    await render(tester, 'assets/icon/icon.png', markShare: 0.72, background: SgColors.band);
    // Android adaptive foreground: the mark inside the 66% safe zone, no background.
    await render(tester, 'assets/icon/foreground.png', markShare: 0.5);
    // Splash: the mark alone.
    await render(tester, 'assets/icon/splash.png', markShare: 0.6);
  });
}
