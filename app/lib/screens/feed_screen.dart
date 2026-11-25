import 'package:material_ui/material_ui.dart';

import '../data/app_state.dart';
import '../models/post.dart';
import '../theme/tokens.dart';
import '../widgets/post_actions.dart';
import '../widgets/post_tile.dart';
import '../widgets/symbol_mark.dart';

/// Timeline with "추천" (everyone) and "팔로잉" tabs.
class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key, required this.state, required this.onOpenProfile});

  final AppState state;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => Column(
          children: [
            SizedBox(
              height: 52,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Semantics(
                      button: true,
                      label: '내 프로필',
                      child: GestureDetector(
                        onTap: onOpenProfile,
                        child: Avatar(
                          initial: state.me?.initial ?? '?',
                          color: avatarPalette[(state.me?.id.hashCode ?? 0).abs() % avatarPalette.length],
                          size: 32,
                        ),
                      ),
                    ),
                    const Expanded(child: Center(child: SymbolMark())),
                    const SizedBox(width: 32),
                  ],
                ),
              ),
            ),
            const TabBar(
              labelColor: SgColors.ink,
              unselectedLabelColor: SgColors.muted,
              labelStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              unselectedLabelStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              indicatorSize: TabBarIndicatorSize.label,
              indicator: UnderlineTabIndicator(
                borderSide: BorderSide(color: SgColors.accent, width: 3),
                borderRadius: BorderRadius.all(Radius.circular(2)),
              ),
              dividerColor: SgColors.line,
              tabs: [
                Tab(text: '추천'),
                Tab(text: '팔로잉'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _PostList(state: state, posts: state.feed, loadMore: state.hasMore ? state.loadMore : null),
                  if (state.me?.followUnlocked ?? false)
                    _PostList(
                      state: state,
                      posts: state.following,
                      empty: '아직 팔로우한 사람이 없어요. 글쓴이 이름을 눌러 프로필에서 팔로우할 수 있어요.',
                    )
                  else
                    _FollowingLocked(days: state.me?.writingDays ?? 0, total: state.me?.daysToFollow ?? 10),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostList extends StatelessWidget {
  const _PostList({required this.state, required this.posts, this.loadMore, this.empty = '아직 올라온 글이 없어요.'});

  final AppState state;
  final List<Post> posts;
  final VoidCallback? loadMore;
  final String empty;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: SgColors.accent,
      onRefresh: state.refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (loadMore != null && n.metrics.extentAfter < 400) loadMore!();
          return false;
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(state.error!, style: SgText.small.copyWith(color: SgColors.accentText)),
              ),
            if (posts.isEmpty && !state.loading)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(empty, textAlign: TextAlign.center, style: SgText.small),
              ),
            for (final p in posts) ConnectedPostTile(key: ValueKey(p.id), state: state, post: p),
            if (state.loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
              ),
          ],
        ),
      ),
    );
  }
}

class _FollowingLocked extends StatelessWidget {
  const _FollowingLocked({required this.days, required this.total});

  final int days;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SymbolMark(size: 48, semanticLabel: null),
          const SizedBox(height: 16),
          Text('${total - days}일 더 쓰면 팔로우할 수 있어요', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('글을 쓴 날이 $total일이 되면 팔로우가 열려요. 연속이 아니어도 돼요.', textAlign: TextAlign.center, style: SgText.small),
        ],
      ),
    );
  }
}
