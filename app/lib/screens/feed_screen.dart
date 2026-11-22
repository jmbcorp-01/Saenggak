import 'package:material_ui/material_ui.dart';

import '../data/post_store.dart';
import '../theme/tokens.dart';
import '../widgets/post_tile.dart';
import '../widgets/symbol_mark.dart';

/// Timeline with "추천" (everyone) and "팔로잉" tabs.
class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key, required this.store, required this.onOpenProfile});

  final PostStore store;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
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
                      child: const Avatar(
                          initial: '윤', color: 0xFF3B4A42, size: 32),
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
            tabs: [Tab(text: '추천'), Tab(text: '팔로잉')],
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: store,
              builder: (context, _) => TabBarView(
                children: [
                  ListView(
                    children: [
                      for (final p in store.posts)
                        PostTile(
                          post: p,
                          onEmpathy: () => store.toggleEmpathy(p.id),
                        ),
                    ],
                  ),
                  _FollowingLocked(store: store),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FollowingLocked extends StatelessWidget {
  const _FollowingLocked({required this.store});

  final PostStore store;

  @override
  Widget build(BuildContext context) {
    final left = PostStore.daysToFollow - store.writingDays;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SymbolMark(size: 48, semanticLabel: null),
          const SizedBox(height: 16),
          Text(
            '$left일 더 쓰면 팔로우할 수 있어요',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            '글을 쓴 날이 10일이 되면 팔로우가 열려요. 연속이 아니어도 돼요.',
            textAlign: TextAlign.center,
            style: SgText.small,
          ),
        ],
      ),
    );
  }
}
