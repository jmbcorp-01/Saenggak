import 'package:material_ui/material_ui.dart';

import '../api/cognito_auth.dart';
import '../theme/tokens.dart';
import '../widgets/symbol_mark.dart';

/// Email sign-up (with the emailed code) and sign-in.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.auth, required this.signUp, required this.onSignedIn});

  final CognitoAuth auth;
  final bool signUp;

  /// Called once a session exists.
  final Future<void> Function() onSignedIn;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  late bool _signUp = widget.signUp;
  bool _needsCode = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() step) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await step();
    } on AuthException catch (e) {
      if (e.type == 'UserNotConfirmedException') {
        await widget.auth.resendCode(_email.text.trim());
        setState(() => _needsCode = true);
      } else {
        setState(() => _error = e.message);
      }
    } catch (_) {
      setState(() => _error = '연결이 불안정해요. 잠시 후 다시 해주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() => _run(() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (_needsCode) {
      await widget.auth.confirm(email, _code.text.trim());
    } else if (_signUp) {
      await widget.auth.signUp(email, password);
      setState(() => _needsCode = true);
      return;
    }
    await widget.auth.signIn(email, password);
    await widget.onSignedIn();
  });

  @override
  Widget build(BuildContext context) {
    final title = _needsCode ? '이메일을 확인해주세요' : (_signUp ? '계정 만들기' : '로그인');
    final pill = RoundedRectangleBorder(borderRadius: BorderRadius.circular(25));
    return Scaffold(
      appBar: AppBar(
        backgroundColor: SgColors.surface,
        surfaceTintColor: Colors.transparent,
        title: const SymbolMark(size: 28),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
          children: [
            Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
            const SizedBox(height: 8),
            Text(
              _needsCode ? '${_email.text.trim()}로 보낸 6자리 코드를 입력해주세요.' : '이메일과 비밀번호로 ${_signUp ? '시작해요' : '들어가요'}.',
              style: const TextStyle(fontSize: 15, color: SgColors.muted),
            ),
            const SizedBox(height: 28),
            if (!_needsCode) ...[
              TextField(
                key: const Key('email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: _field('이메일'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('password'),
                controller: _password,
                obscureText: true,
                autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
                decoration: _field(_signUp ? '비밀번호 (10자 이상)' : '비밀번호'),
                onSubmitted: (_) => _submit(),
              ),
            ] else
              TextField(
                key: const Key('code'),
                controller: _code,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                decoration: _field('인증 코드'),
                onSubmitted: (_) => _submit(),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(fontSize: 14, color: SgColors.accentText)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('auth-submit'),
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: SgColors.ink,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: pill,
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(_needsCode ? '인증하기' : (_signUp ? '다음' : '로그인')),
            ),
            const SizedBox(height: 8),
            if (_needsCode)
              TextButton(
                onPressed: _busy ? null : () => _run(() => widget.auth.resendCode(_email.text.trim())),
                style: TextButton.styleFrom(foregroundColor: SgColors.muted),
                child: const Text('코드 다시 받기'),
              )
            else
              TextButton(
                onPressed: () => setState(() {
                  _signUp = !_signUp;
                  _error = null;
                }),
                style: TextButton.styleFrom(foregroundColor: SgColors.accentText),
                child: Text(_signUp ? '이미 계정이 있어요' : '새 계정 만들기'),
              ),
          ],
        ),
      ),
    );
  }

  InputDecoration _field(String label) => InputDecoration(
    labelText: label,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: SgColors.outline),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: SgColors.ink, width: 1.5),
    ),
  );
}
