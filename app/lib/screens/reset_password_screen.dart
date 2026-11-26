import 'package:material_ui/material_ui.dart';

import '../api/cognito_auth.dart';
import '../theme/tokens.dart';

/// Sets a new password with a code sent to the account's email.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.auth, this.email = ''});

  final CognitoAuth auth;
  final String email;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  late final _email = TextEditingController(text: widget.email);
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!_codeSent) {
        await widget.auth.forgotPassword(email);
        if (mounted) setState(() => _codeSent = true);
      } else {
        await widget.auth.resetPassword(email, _code.text.trim(), _password.text);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('새 비밀번호로 로그인해주세요.')));
        Navigator.of(context).pop();
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '연결이 불안정해요. 잠시 후 다시 해주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(10));
    return Scaffold(
      appBar: AppBar(title: const Text('비밀번호 다시 만들기')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
          children: [
            Text(
              _codeSent ? '${_email.text.trim()}로 보낸 6자리 코드와 새 비밀번호를 입력해주세요.' : '가입한 이메일로 코드를 보내드려요.',
              style: TextStyle(fontSize: 15, color: SgColors.muted, height: 1.5),
            ),
            const SizedBox(height: 24),
            TextField(
              key: const Key('reset-email'),
              controller: _email,
              enabled: !_codeSent,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(labelText: '이메일', border: border),
            ),
            if (_codeSent) ...[
              const SizedBox(height: 12),
              TextField(
                key: const Key('reset-code'),
                controller: _code,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                decoration: InputDecoration(labelText: '인증 코드', border: border),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('reset-password'),
                controller: _password,
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(labelText: '새 비밀번호 (10자 이상)', border: border),
                onSubmitted: (_) => _submit(),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(fontSize: 14, color: SgColors.accentText)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('reset-submit'),
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: SgColors.ink,
                foregroundColor: SgColors.onInk,
                minimumSize: const Size.fromHeight(50),
              ),
              child: Text(_codeSent ? '비밀번호 바꾸기' : '코드 받기'),
            ),
          ],
        ),
      ),
    );
  }
}
