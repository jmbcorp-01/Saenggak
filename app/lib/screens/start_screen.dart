import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';
import '../widgets/appear.dart';
import '../widgets/drawn_symbol.dart';

/// First screen: what the app is, and the way in.
class StartScreen extends StatelessWidget {
  const StartScreen({super.key, required this.onSignUp, required this.onSignIn});

  final VoidCallback onSignUp;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            // Wide screens: the symbol large on the left, the words and the
            // way in on the right.
            if (c.maxWidth >= 900) {
              return MouseArea(
                child: Row(
                  children: [
                    Expanded(
                      child: Center(
                        child: LeanToMouse(
                          child: DrawnSymbol(
                            size: math.min(c.maxHeight * 0.55, 380),
                            delay: const Duration(milliseconds: 400),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 460,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(SgSpace.xl, SgSpace.xxl, 64, SgSpace.xxl),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Appear(delay: const Duration(milliseconds: 500), child: _headline(48)),
                            const SizedBox(height: 56),
                            Appear(delay: const Duration(milliseconds: 800), child: _actions()),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }
            // Phones, and tablets with the same layout in a narrower column.
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 40, 32, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: DrawnSymbol(size: 44, breaths: 0, delay: Duration(milliseconds: 400))),
                      const Spacer(),
                      Appear(delay: const Duration(milliseconds: 400), child: _headline(34)),
                      const Spacer(),
                      Appear(delay: const Duration(milliseconds: 600), child: _actions()),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _headline(double size) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '사람이 직접 쓴\n생각만 있는 곳.',
        style: TextStyle(
          fontSize: size,
          height: 1.3,
          fontWeight: FontWeight.w700,
          letterSpacing: -size / 34,
          color: SgColors.ink,
        ),
      ),
      const SizedBox(height: 16),
      Text(
        // On a wide screen the two sentences sit on their own lines.
        size > 40 ? 'AI도, 붙여넣기도 없이.\n하루에 한 생각이라도 당신의 손으로.' : 'AI도, 붙여넣기도 없이. 하루에 한 생각이라도 당신의 손으로.',
        style: TextStyle(fontSize: size > 40 ? 18 : 16, height: 1.6, color: SgColors.muted),
      ),
    ],
  );

  Widget _actions() {
    final pill = RoundedRectangleBorder(borderRadius: BorderRadius.circular(25));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HoverLift(
          child: FilledButton(
            onPressed: onSignUp,
            style: FilledButton.styleFrom(
              backgroundColor: SgColors.ink,
              foregroundColor: SgColors.onInk,
              minimumSize: const Size.fromHeight(50),
              shape: pill,
              textStyle: SgText.label(size: 16, weight: FontWeight.w700),
            ),
            child: const Text('계정 만들기'),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: Divider()),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('이미 계정이 있나요?', style: SgText.small),
            ),
            Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 12),
        HoverLift(
          child: OutlinedButton(
            onPressed: onSignIn,
            style: OutlinedButton.styleFrom(
              foregroundColor: SgColors.accentText,
              side: BorderSide(color: SgColors.outline),
              minimumSize: const Size.fromHeight(50),
              shape: pill,
              textStyle: SgText.label(size: 16, weight: FontWeight.w700),
            ),
            child: const Text('로그인'),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: () {},
              style: TextButton.styleFrom(foregroundColor: SgColors.ink),
              child: const Text('한국어', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            TextButton(
              onPressed: () {},
              style: TextButton.styleFrom(foregroundColor: SgColors.muted),
              child: const Text('English'),
            ),
          ],
        ),
      ],
    );
  }
}
