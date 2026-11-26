import 'package:material_ui/material_ui.dart';

import '../data/app_state.dart';
import '../models/post.dart' show avatarPalette, timeAgo;
import '../theme/tokens.dart';
import '../widgets/post_tile.dart' show Avatar;
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
        return RefreshIndicator(
          onRefresh: state.loadNotifications,
          child: items.isEmpty
              ? ListView(
                  children: [
                    SizedBox(height: 160),
                    Center(child: Text('아직 알림이 없어요.', style: SgText.small)),
                    SizedBox(height: 8),
                    Center(child: Text('누군가 공감하거나 팔로우하면 여기에 보여요.', style: SgText.small)),
                  ],
                )
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: SgColors.line),
                  itemBuilder: (context, i) {
                    final n = items[i];
                    final what = n.kind == 'follow' ? '님이 나를 팔로우해요.' : '님이 내 생각에 공감했어요.';
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
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => Scaffold(
                            appBar: AppBar(backgroundColor: SgColors.surface, surfaceTintColor: Colors.transparent),
                            body: ProfileScreen(state: state, userId: n.actorId),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
