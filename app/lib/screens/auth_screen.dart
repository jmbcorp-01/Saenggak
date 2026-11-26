import 'package:material_ui/material_ui.dart';

import '../api/cognito_auth.dart';
import '../core/links.dart';
import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import '../widgets/symbol_mark.dart';
import 'reset_password_screen.dart';

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
      setState(() => _error = t('연결이 불안정해요. 잠시 후 다시 해주세요.'));
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
    final title = _needsCode ? t('이메일을 확인해주세요') : (_signUp ? t('계정 만들기') : t('로그인'));
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
          padding: formPadding(context),
          children: [
            Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
            const SizedBox(height: 8),
            Text(
              _needsCode
                  ? t('{0}로 보낸 6자리 코드를 입력해주세요.', [_email.text.trim()])
                  : (_signUp ? t('이메일과 비밀번호로 시작해요.') : t('이메일과 비밀번호로 들어가요.')),
              style: TextStyle(fontSize: 15, color: SgColors.muted),
            ),
            const SizedBox(height: 28),
            if (!_needsCode) ...[
              TextField(
                key: const Key('email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: _field(t('이메일')),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('password'),
                controller: _password,
                obscureText: true,
                autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
                decoration: _field(_signUp ? t('비밀번호 (10자 이상)') : t('비밀번호')),
                onSubmitted: (_) => _submit(),
              ),
            ] else
              TextField(
                key: const Key('code'),
                controller: _code,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                decoration: _field(t('인증 코드')),
                onSubmitted: (_) => _submit(),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(fontSize: 14, color: SgColors.accentText)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('auth-submit'),
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: SgColors.ink,
                foregroundColor: SgColors.onInk,
                minimumSize: const Size.fromHeight(50),
                shape: pill,
                textStyle: SgText.label(size: 16, weight: FontWeight.w700),
              ),
              child: _busy
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: SgColors.onInk),
                    )
                  : Text(_needsCode ? t('인증하기') : (_signUp ? t('다음') : t('로그인'))),
            ),
            if (_signUp && !_needsCode)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(t('가입하면 '), style: SgText.small),
                    InkWell(
                      onTap: () => openPage('terms.html'),
                      child: Text(t('이용약관'), style: TextStyle(fontSize: 13, decoration: TextDecoration.underline)),
                    ),
                    Text(t('과 '), style: SgText.small),
                    InkWell(
                      onTap: () => openPage('privacy.html'),
                      child: Text(t('개인정보 처리방침'), style: TextStyle(fontSize: 13, decoration: TextDecoration.underline)),
                    ),
                    Text(t('에 동의하게 돼요. 만 14세 이상만 가입할 수 있어요.'), style: SgText.small),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            if (_needsCode)
              TextButton(
                onPressed: _busy ? null : () => _run(() => widget.auth.resendCode(_email.text.trim())),
                style: TextButton.styleFrom(foregroundColor: SgColors.muted),
                child: Text(t('코드 다시 받기')),
              )
            else
              TextButton(
                onPressed: () => setState(() {
                  _signUp = !_signUp;
                  _error = null;
                }),
                style: TextButton.styleFrom(foregroundColor: SgColors.accentText),
                child: Text(_signUp ? t('이미 계정이 있어요') : t('새 계정 만들기')),
              ),
            if (!_needsCode && !_signUp)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ResetPasswordScreen(auth: widget.auth, email: _email.text.trim()),
                        ),
                      ),
                style: TextButton.styleFrom(foregroundColor: SgColors.muted),
                child: Text(t('비밀번호를 잊었어요')),
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
      borderSide: BorderSide(color: SgColors.outline),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: SgColors.ink, width: 1.5),
    ),
  );
}
