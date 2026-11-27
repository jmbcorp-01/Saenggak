import 'package:material_ui/material_ui.dart';

import '../core/nav.dart';
import '../core/push.dart';
import '../data/app_state.dart';
import '../l10n/l10n.dart';
import '../models/post.dart' show avatarPalette, timeAgo;
import '../theme/tokens.dart';
import '../widgets/post_tile.dart' show Avatar;
import 'post_screen.dart';
import 'profile_screen.dart';

/// 공감 on the reader's posts and new followers.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final items = state.notifications;
        final now = state.clock();
        final list = RefreshIndicator(
          onRefresh: state.loadNotifications,
          child: items.isEmpty
              ? ListView(
                  children: [
                    SizedBox(height: 160),
                    Center(child: Text(t('아직 알림이 없어요.'), style: SgText.small)),
                    SizedBox(height: 8),
                    Center(child: Text(t('누군가 공감하거나 팔로우하면 여기에 보여요.'), style: SgText.small)),
                  ],
                )
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: SgColors.line),
                  itemBuilder: (context, i) {
                    final n = items[i];
                    final what = switch (n.kind) {
                      'follow' => t('님이 나를 팔로우해요.'),
                      'post' => t('님이 새 생각을 남겼어요.'),
                      _ => t('님이 내 생각에 공감했어요.'),
                    };
                    return ListTile(
                      leading: Avatar(
                        initial: n.actorName.isEmpty ? '?' : n.actorName.substring(0, 1),
                        color: avatarPalette[n.actorId.hashCode.abs() % avatarPalette.length],
                        photoUrl: n.actorPhotoUrl,
                      ),
                      title: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: n.actorName, style: SgText.name),
                            TextSpan(text: ' $what'),
                          ],
                        ),
                      ),
                      subtitle: Text(
                        [if (n.excerpt != null) '“${n.excerpt}”', timeAgo(n.at, now)].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // A new post opens the post itself; the rest open the person.
                      onTap: () => n.kind == 'post' && n.postId != null
                          ? pushPage<void>(context, (_) => PostScreen(state: state, postId: n.postId!))
                          : pushPage<void>(context, (_) => ProfilePage(state: state, userId: n.actorId)),
                    );
                  },
                ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: SgSpace.lg),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: SgColors.line)),
              ),
              child: Semantics(header: true, child: Text(t('알림'), style: SgText.title)),
            ),
            if (state.pushPermission == PushPermission.notAsked || state.pushPermission == PushPermission.denied)
              _PushBanner(state: state),
            Expanded(child: list),
          ],
        );
      },
    );
  }
}

/// Offers push alerts until the person turns them on, or says how to when
/// the device or browser blocks them.
class _PushBanner extends StatelessWidget {
  const _PushBanner({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final denied = state.pushPermission == PushPermission.denied;
    return Container(
      key: const Key('push-banner'),
      padding: const EdgeInsets.fromLTRB(SgSpace.lg, 12, SgSpace.sm, 12),
      decoration: BoxDecoration(
        color: SgColors.band,
        border: Border(bottom: BorderSide(color: SgColors.line)),
      ),
      child: Row(
        children: [
          Icon(Icons.notifications_active_outlined, color: SgColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              denied ? t('알림이 막혀 있어요. 기기나 브라우저 설정에서 생각의 알림을 허용해 주세요.') : t('앱을 닫아도 공감과 팔로우 소식을 알려드릴게요.'),
              style: SgText.small,
            ),
          ),
          if (!denied)
            TextButton(
              key: const Key('push-enable'),
              onPressed: () => state.startPush(ask: true),
              child: Text(t('알림 켜기')),
            ),
        ],
      ),
    );
  }
}
