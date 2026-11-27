import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/appearance.dart';
import '../core/links.dart';
import '../data/app_state.dart';
import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import 'admin_screen.dart';
import 'blocked_screen.dart';
import 'photo_capture_screen.dart';
import 'profile_setup_screen.dart';
import 'saved_screen.dart';
import '../core/save_file.dart';
import '../models/growth.dart';

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
        title: Text(t('시간대')),
        children: [
          for (final z in zones)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, z),
              child: Row(
                children: [
                  Expanded(child: Text(z == device ? t('{0} (이 기기)', [z]) : z)),
                  if (z == current) const Icon(Icons.check, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked != null && picked != current && context.mounted) {
      await _run(context, () => state.saveSettings(timeZone: picked), t('시간대를 바꾸지 못했어요.'));
    }
  }

  Future<void> _export(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final json = await state.backend.exportData();
      final downloaded = await saveTextFile('saenggak-${state.me?.handle ?? 'export'}.json', json);
      messenger.showSnackBar(
        SnackBar(content: Text(downloaded ? t('내 기록을 내려받았어요.') : t('내 기록을 복사했어요. 메모나 메일에 붙여넣어 보관하세요.'))),
      );
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(t('내 기록을 내보내지 못했어요.'))));
    }
  }

  Future<void> _shareInvite(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final url = await state.inviteUrl();
    if (url == null) {
      messenger.showSnackBar(SnackBar(content: Text(t('초대 링크를 만들지 못했어요. 다시 시도해주세요.'))));
      return;
    }
    await Clipboard.setData(ClipboardData(text: t('손으로 직접 쓴 생각만 올라오는 곳이에요. 같이 써요. {0}', [url])));
    messenger.showSnackBar(SnackBar(content: Text(t('초대 링크를 복사했어요. 메신저에 붙여넣어 보내세요.'))));
  }

  Future<void> _signOut(BuildContext context) async {
    await state.signOut();
    if (context.mounted) Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil('/', (_) => false);
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('계정을 삭제할까요?')),
        content: Text(
          t('쓴 글, 받은 공감, 팔로우, 프로필 사진이 모두 지워지고 되돌릴 수 없어요. 같은 이메일로 다시 가입하면 처음부터 시작해요.'),
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('취소'))),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: SgColors.accentText),
            child: Text(t('삭제')),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    try {
      await state.deleteAccount();
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil('/', (_) => false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('계정을 삭제했어요.'))));
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('계정을 삭제하지 못했어요. 잠시 후 다시 시도해주세요.'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('설정'))),
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final me = state.me;
          if (me == null) return const SizedBox.shrink();
          return ListView(
            children: [
              _Header(t('계정')),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(t('프로필 수정')),
                onTap: () =>
                    _push(context, (c) => ProfileSetupScreen(state: state, onDone: () => Navigator.of(c).pop())),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text(t('프로필 사진 찍기')),
                onTap: () => Navigator.of(
                  context,
                  rootNavigator: true,
                ).push(MaterialPageRoute<void>(builder: (_) => PhotoCaptureScreen(state: state))),
              ),
              ListTile(
                leading: const Icon(SgIcons.bookmark),
                title: Text(t('저장한 글')),
                onTap: () => _push(context, (_) => SavedScreen(state: state)),
              ),
              ListTile(
                key: const Key('export'),
                leading: const Icon(Icons.download_outlined),
                title: Text(t('내 기록 내보내기')),
                subtitle: Text(t('프로필, 쓴 글, 공감, 팔로우를 파일 하나로 받아요.')),
                onTap: () => _export(context),
              ),
              _Header(t('공유와 초대')),
              _SharingTiles(state: state, run: (step, failed) => _run(context, step, failed)),
              ListTile(
                key: const Key('invite-link'),
                leading: const Icon(Icons.link),
                title: Text(t('내 초대 링크')),
                subtitle: Text(t('친구가 이 링크로 들어오면 누가 초대했는지 기록돼요.')),
                trailing: const Icon(Icons.ios_share, size: 20),
                onTap: () => _shareInvite(context),
              ),
              _Header(t('화면')),
              ListTile(
                leading: const Icon(Icons.contrast_rounded),
                title: Text(t('화면 모드')),
                subtitle: Text(t('밝게, 어둡게, 또는 기기 설정을 따라요.')),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
                child: ValueListenableBuilder(
                  valueListenable: Appearance.instance,
                  builder: (context, mode, _) => SegmentedButton<ThemeMode>(
                    key: const Key('theme-mode'),
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(value: ThemeMode.system, label: Text(t('기기 설정'))),
                      ButtonSegment(value: ThemeMode.light, label: Text(t('밝게'))),
                      ButtonSegment(value: ThemeMode.dark, label: Text(t('어둡게'))),
                    ],
                    selected: {mode},
                    onSelectionChanged: (v) => Appearance.instance.set(v.first),
                  ),
                ),
              ),
              _Header(t('언어와 지역')),
              ListTile(
                leading: const Icon(Icons.translate),
                title: Text(t('언어')),
                subtitle: Text(t('화면에 쓰는 언어예요. 다른 언어로 쓴 글도 이 언어로 번역해서 보여드려요.')),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'ko', label: Text('한국어')),
                    ButtonSegment(value: 'en', label: Text('English')),
                  ],
                  selected: {AppLang.instance.value},
                  onSelectionChanged: (v) => _run(context, () => state.setLanguage(v.first), t('언어를 바꾸지 못했어요.')),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.schedule),
                title: Text(t('시간대')),
                subtitle: Text(t('{0} · 쓴 날은 이 시간대의 날짜로 세요.', [me.timeZone])),
                onTap: () => _pickTimeZone(context),
              ),
              if (me.isAdmin) ...[
                _Header(t('운영')),
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings_outlined),
                  title: Text(t('관리자 페이지')),
                  onTap: () => _push(context, (_) => AdminScreen(state: state)),
                ),
              ],
              ListTile(
                leading: const Icon(Icons.block),
                title: Text(t('차단한 사람')),
                onTap: () => _push(context, (_) => BlockedScreen(state: state)),
              ),
              _Header(t('정보')),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(t('이용약관')),
                onTap: () => openPage('terms.html'),
              ),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: Text(t('개인정보 처리방침')),
                onTap: () => openPage('privacy.html'),
              ),
              ListTile(
                leading: const Icon(Icons.mail_outline),
                title: Text(t('문의하기')),
                onTap: () => openPage('support.html'),
              ),
              const Divider(height: 32),
              ListTile(leading: const Icon(Icons.logout), title: Text(t('로그아웃')), onTap: () => _signOut(context)),
              ListTile(
                leading: Icon(Icons.delete_outline, color: SgColors.accentText),
                title: Text(t('계정 삭제'), style: TextStyle(color: SgColors.accentText)),
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

/// The writer's consent for Saenggak's own accounts and public pages. Off
/// until they turn it on; the second switch leaves their name out.
class _SharingTiles extends StatefulWidget {
  const _SharingTiles({required this.state, required this.run});

  final AppState state;
  final Future<void> Function(Future<void> Function() step, String failed) run;

  @override
  State<_SharingTiles> createState() => _SharingTilesState();
}

class _SharingTilesState extends State<_SharingTiles> {
  @override
  void initState() {
    super.initState();
    if (widget.state.sharing == null) widget.state.loadSharing().catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    final sharing = widget.state.sharing;
    final on = sharing?.shareOk ?? false;
    void set(SharingSettings next) => widget.run(
      () => widget.state.setSharing(shareOk: next.shareOk, anonymous: next.anonymous),
      t('바꾸지 못했어요. 다시 시도해주세요.'),
    );
    return Column(
      children: [
        SwitchListTile(
          key: const Key('share-ok'),
          secondary: const Icon(Icons.campaign_outlined),
          title: Text(t('생각 공식 계정에 내 글 소개 허용')),
          subtitle: Text(
            t('켜면 생각의 인스타그램, 스레드와 공개 웹페이지에 내 글이 소개될 수 있어요. 올리기 전에 운영자가 한 편씩 확인해요. 끄면 앞으로 소개되지 않고, 이미 올린 글도 내려요.'),
          ),
          value: on,
          onChanged: sharing == null ? null : (v) => set(SharingSettings(shareOk: v, anonymous: sharing.anonymous)),
        ),
        if (on)
          SwitchListTile(
            key: const Key('share-anonymous'),
            secondary: const SizedBox(width: 24),
            title: Text(t('이름 없이 소개')),
            subtitle: Text(t('닉네임 대신 "어느 생각러"로 보여요.')),
            value: sharing!.anonymous,
            onChanged: (v) => set(SharingSettings(shareOk: true, anonymous: v)),
          ),
      ],
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
