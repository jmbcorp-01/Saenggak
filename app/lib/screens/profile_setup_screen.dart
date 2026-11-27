import 'package:material_ui/material_ui.dart';

import '../api/backend.dart';
import '../data/app_state.dart';
import '../l10n/l10n.dart';
import '../theme/tokens.dart';

/// Name, @handle and a short bio. Shown once after sign-up, and from
/// "프로필 수정" later.
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key, required this.state, required this.onDone, this.firstTime = false});

  final AppState state;
  final VoidCallback onDone;
  final bool firstTime;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  late final _name = TextEditingController(text: widget.state.me?.displayName ?? '');
  late final _handle = TextEditingController(text: widget.state.me?.handle ?? '');
  late final _bio = TextEditingController(text: widget.state.me?.bio ?? '');

  /// Only on a new profile: the code of whoever or whatever brought them.
  late final _code = TextEditingController(text: widget.state.pendingCode ?? '');
  bool _busy = false;
  String? _error;

  static final _handlePattern = RegExp(r'^[a-z0-9_]{3,20}$');

  @override
  void dispose() {
    _name.dispose();
    _handle.dispose();
    _bio.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final handle = _handle.text.trim().toLowerCase();
    final name = _name.text.trim();
    if (name.isEmpty || name.length > 30) {
      setState(() => _error = t('이름은 1자에서 30자 사이로 써주세요.'));
      return;
    }
    if (!_handlePattern.hasMatch(handle)) {
      setState(() => _error = t('아이디는 영문 소문자, 숫자, _ 로 3자에서 20자 사이예요.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.state.saveProfile(handle: handle, displayName: name, bio: _bio.text.trim());
      final code = _code.text.trim();
      if (widget.firstTime && code.isNotEmpty) {
        try {
          await widget.state.recordSource(code);
        } on ApiException catch (e) {
          if (e.code == 'unknown_code') {
            setState(() => _error = t('없는 초대 코드예요. 다시 확인하거나 비워 두세요.'));
            return;
          }
          // Anything else is not worth holding the new person back for.
        } catch (_) {}
      }
      widget.onDone();
    } on ApiException catch (e) {
      setState(
        () => _error = switch (e.code) {
          'handle_taken' => t('이미 쓰고 있는 아이디예요.'),
          'profile_blocked' => t('닉네임이나 소개에 쓸 수 없는 표현이 있어요.'),
          'rate_limited' => t('잠시 후 다시 저장해주세요.'),
          _ => t('저장하지 못했어요. 다시 시도해주세요.'),
        },
      );
    } catch (_) {
      setState(() => _error = t('저장하지 못했어요. 다시 시도해주세요.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: SgColors.surface,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: !widget.firstTime,
        title: Text(
          widget.firstTime ? t('프로필 만들기') : t('프로필 수정'),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            key: const Key('profile-save'),
            onPressed: _busy ? null : _save,
            style: TextButton.styleFrom(foregroundColor: SgColors.ink),
            child: Text(t('저장'), style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: formPadding(context, side: 24),
        children: [
          if (widget.firstTime) ...[
            Text(t('다른 사람에게 보이는 이름이에요.'), style: TextStyle(fontSize: 15, color: SgColors.muted)),
            const SizedBox(height: 20),
          ],
          TextField(
            key: const Key('name'),
            controller: _name,
            maxLength: 30,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(labelText: t('닉네임')),
          ),
          TextField(
            key: const Key('handle'),
            controller: _handle,
            maxLength: 20,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(labelText: t('아이디'), prefixText: '@'),
          ),
          TextField(
            key: const Key('bio'),
            controller: _bio,
            maxLength: 160,
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(labelText: t('소개 (선택)')),
          ),
          if (widget.firstTime)
            TextField(
              key: const Key('invite-code'),
              controller: _code,
              maxLength: 32,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: t('초대 코드 (선택)'), helperText: t('초대받았다면 받은 코드를 넣어 주세요.')),
            ),
          if (_error != null) Text(_error!, style: TextStyle(fontSize: 14, color: SgColors.accentText)),
        ],
      ),
    );
  }
}
