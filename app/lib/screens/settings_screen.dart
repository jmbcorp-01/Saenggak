import 'package:material_ui/material_ui.dart';

import '../core/links.dart';
import '../data/app_state.dart';
import '../theme/tokens.dart';
import 'admin_screen.dart';
import 'blocked_screen.dart';
import 'photo_capture_screen.dart';
import 'profile_setup_screen.dart';

/// Time zones offered besides the device's own. Writing days follow the
/// writer's calendar day, so this only matters for people who travel.
const commonTimeZones = [
  'Asia/Seoul',
  'Asia/Tokyo',
  'Asia/Shanghai',
  'Asia/Singapore',
  'Australia/Sydney',
  'Europe/London',
  'Europe/Paris',
  'America/New_York',
  'America/Chicago',
  'America/Los_Angeles',
  'Pacific/Honolulu',
];

/// Account and app settings: profile, feed language, time zone, admin pages,
/// sign-out and account deletion.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.state});

  final AppState state;

  void _push(BuildContext context, Widget Function(BuildContext) builder) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));

  Future<void> _run(BuildContext context, Future<void> Function() step, String failed) async {
    try {
      await step();
    } catch (_) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  Future<void> _pickTimeZone(BuildContext context) async {
    final device = await state.deviceTimeZone();
    if (!context.mounted) return;
    final current = state.me!.timeZone;
    final zones = {device, current, ...commonTimeZones}.toList();
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('시간대'),
        children: [
          for (final z in zones)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, z),
              child: Row(
                children: [
                  Expanded(child: Text(z == device ? '$z (이 기기)' : z)),
                  if (z == current) const Icon(Icons.check, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked != null && picked != current && context.mounted) {
      await _run(context, () => state.saveSettings(timeZone: picked), '시간대를 바꾸지 못했어요.');
    }
  }

  Future<void> _signOut(BuildContext context) async {
    await state.signOut();
    if (context.mounted) Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('계정을 삭제할까요?'),
        content: const Text(
          '쓴 글, 받은 공감, 팔로우, 프로필 사진이 모두 지워지고 되돌릴 수 없어요. 같은 이메일로 다시 가입하면 처음부터 시작해요.',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: SgColors.accentText),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    try {
      await state.deleteAccount();
      if (!context.mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('계정을 삭제했어요.')));
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('계정을 삭제하지 못했어요. 잠시 후 다시 시도해주세요.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final me = state.me;
          if (me == null) return const SizedBox.shrink();
          return ListView(
            children: [
              const _Header('계정'),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('프로필 수정'),
                onTap: () =>
                    _push(context, (c) => ProfileSetupScreen(state: state, onDone: () => Navigator.of(c).pop())),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('프로필 사진 찍기'),
                onTap: () => _push(context, (_) => PhotoCaptureScreen(state: state)),
              ),
              const _Header('피드'),
              ListTile(
                leading: const Icon(Icons.translate),
                title: const Text('글을 읽을 언어'),
                subtitle: const Text('다른 언어로 쓴 글은 이 언어로 번역해서 보여드려요.'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'ko', label: Text('한국어')),
                    ButtonSegment(value: 'en', label: Text('English')),
                  ],
                  selected: {me.locale},
                  onSelectionChanged: (v) => _run(context, () => state.saveSettings(locale: v.first), '언어를 바꾸지 못했어요.'),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.schedule),
                title: const Text('시간대'),
                subtitle: Text('${me.timeZone} · 쓴 날은 이 시간대의 날짜로 세요.'),
                onTap: () => _pickTimeZone(context),
              ),
              if (me.isAdmin) ...[
                const _Header('운영'),
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings_outlined),
                  title: const Text('관리자 페이지'),
                  onTap: () => _push(context, (_) => AdminScreen(state: state)),
                ),
              ],
              ListTile(
                leading: const Icon(Icons.block),
                title: const Text('차단한 사람'),
                onTap: () => _push(context, (_) => BlockedScreen(state: state)),
              ),
              const _Header('정보'),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('이용약관'),
                onTap: () => openPage('terms.html'),
              ),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('개인정보 처리방침'),
                onTap: () => openPage('privacy.html'),
              ),
              ListTile(
                leading: const Icon(Icons.mail_outline),
                title: const Text('문의하기'),
                onTap: () => openPage('support.html'),
              ),
              const Divider(height: 32),
              ListTile(leading: const Icon(Icons.logout), title: const Text('로그아웃'), onTap: () => _signOut(context)),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: SgColors.accentText),
                title: const Text('계정 삭제', style: TextStyle(color: SgColors.accentText)),
                onTap: () => _deleteAccount(context),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(text, style: SgText.meta),
  );
}
