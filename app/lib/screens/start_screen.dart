import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';
import '../widgets/symbol_mark.dart';

/// First screen: what the app is, and the way in.
class StartScreen extends StatelessWidget {
  const StartScreen({super.key, required this.onSignUp, required this.onSignIn});

  final VoidCallback onSignUp;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final pill = RoundedRectangleBorder(borderRadius: BorderRadius.circular(25));
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 40, 32, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: SymbolMark(size: 44)),
              const Spacer(),
              Text(
                '사람이 직접 쓴\n생각만 있는 곳.',
                style: TextStyle(
                  fontSize: 34,
                  height: 1.3,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1,
                  color: SgColors.ink,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'AI도, 붙여넣기도 없이. 하루에 한 생각이라도 당신의 손으로.',
                style: TextStyle(fontSize: 16, height: 1.6, color: SgColors.muted),
              ),
              const Spacer(),
              FilledButton(
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
              OutlinedButton(
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
          ),
        ),
      ),
    );
  }
}
