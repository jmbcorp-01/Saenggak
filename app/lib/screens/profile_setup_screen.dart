import 'package:material_ui/material_ui.dart';

import '../api/backend.dart';
import '../data/app_state.dart';
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
  bool _busy = false;
  String? _error;

  static final _handlePattern = RegExp(r'^[a-z0-9_]{3,20}$');

  @override
  void dispose() {
    _name.dispose();
    _handle.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final handle = _handle.text.trim().toLowerCase();
    final name = _name.text.trim();
    if (name.isEmpty || name.length > 30) {
      setState(() => _error = '이름은 1자에서 30자 사이로 써주세요.');
      return;
    }
    if (!_handlePattern.hasMatch(handle)) {
      setState(() => _error = '아이디는 영문 소문자, 숫자, _ 로 3자에서 20자 사이예요.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.state.saveProfile(handle: handle, displayName: name, bio: _bio.text.trim());
      widget.onDone();
    } on ApiException catch (e) {
      setState(() => _error = e.code == 'handle_taken' ? '이미 쓰고 있는 아이디예요.' : '저장하지 못했어요. 다시 시도해주세요.');
    } catch (_) {
      setState(() => _error = '저장하지 못했어요. 다시 시도해주세요.');
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
          widget.firstTime ? '프로필 만들기' : '프로필 수정',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            key: const Key('profile-save'),
            onPressed: _busy ? null : _save,
            style: TextButton.styleFrom(foregroundColor: SgColors.ink),
            child: const Text('저장', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (widget.firstTime) ...[
            const Text('다른 사람에게 보이는 이름이에요.', style: TextStyle(fontSize: 15, color: SgColors.muted)),
            const SizedBox(height: 20),
          ],
          TextField(
            key: const Key('name'),
            controller: _name,
            maxLength: 30,
            decoration: const InputDecoration(labelText: '이름'),
          ),
          TextField(
            key: const Key('handle'),
            controller: _handle,
            maxLength: 20,
            autocorrect: false,
            decoration: const InputDecoration(labelText: '아이디', prefixText: '@'),
          ),
          TextField(
            key: const Key('bio'),
            controller: _bio,
            maxLength: 160,
            maxLines: 3,
            minLines: 1,
            decoration: const InputDecoration(labelText: '소개 (선택)'),
          ),
          if (_error != null) Text(_error!, style: const TextStyle(fontSize: 14, color: SgColors.accentText)),
        ],
      ),
    );
  }
}
