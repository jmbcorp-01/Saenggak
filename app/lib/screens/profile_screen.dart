import 'package:material_ui/material_ui.dart';

import '../data/post_store.dart';
import '../theme/tokens.dart';
import '../widgets/post_tile.dart';
import '../widgets/symbol_mark.dart';

/// The writer's own profile: photo, counts, follow progress and posts.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.store, required this.onEdit});

  final PostStore store;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final unlocked = store.writingDays >= PostStore.daysToFollow;
        final received = store.mine.fold<int>(0, (s, p) => s + p.empathyCount);
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              height: 104,
              decoration: const BoxDecoration(color: SgColors.band),
              alignment: Alignment.topRight,
              clipBehavior: Clip.hardEdge,
              child: const Padding(
                padding: EdgeInsets.only(right: 0),
                child: SymbolMark(
                  size: 150,
                  strokeColor: SgColors.bandMark,
                  dotColor: SgColors.bandMark,
                  semanticLabel: null,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Transform.translate(
                    offset: const Offset(0, -40),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                              ),
                              padding: const EdgeInsets.all(4),
                              child: const Avatar(
                                initial: '윤',
                                color: 0xFF3B4A42,
                                size: 72,
                                label: '윤서 프로필 사진',
                              ),
                            ),
                            Positioned(
                              right: -6,
                              bottom: -6,
                              child: IconButton.filled(
                                tooltip: '프로필 사진 바꾸기',
                                onPressed: () {},
                                style: IconButton.styleFrom(
                                  backgroundColor: SgColors.ink,
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(
                                      color: Colors.white, width: 2),
                                ),
                                iconSize: 14,
                                icon: const Icon(Icons.photo_camera_outlined),
                              ),
                            ),
                          ],
                        ),
                        OutlinedButton(
                          onPressed: () {},
                          style: OutlinedButton.styleFrom(
                            foregroundColor: SgColors.ink,
                            side: const BorderSide(color: SgColors.outline),
                            textStyle: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                          child: const Text('프로필 수정'),
                        ),
                      ],
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(0, -28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('윤서',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w700)),
                        const Text('@yoonseo', style: SgText.meta),
                        const SizedBox(height: 12),
                        const Text('조용한 날에 생각을 씁니다.',
                            style: TextStyle(fontSize: 15, height: 1.5)),
                        const SizedBox(height: 10),
                        Text.rich(
                          TextSpan(style: SgText.small, children: [
                            TextSpan(
                                text: unlocked ? '0' : '–',
                                style: const TextStyle(
                                    color: SgColors.ink,
                                    fontWeight: FontWeight.w700)),
                            const TextSpan(text: ' 팔로잉    '),
                            TextSpan(
                                text: unlocked ? '0' : '–',
                                style: const TextStyle(
                                    color: SgColors.ink,
                                    fontWeight: FontWeight.w700)),
                            const TextSpan(text: ' 팔로워    '),
                            TextSpan(
                                text: '$received',
                                style: const TextStyle(
                                    color: SgColors.ink,
                                    fontWeight: FontWeight.w700)),
                            const TextSpan(text: ' 받은 공감'),
                          ]),
                        ),
                        if (!unlocked) ...[
                          const SizedBox(height: 14),
                          FollowProgress(days: store.writingDays),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (store.mine.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text('아직 쓴 글이 없어요.',
                    textAlign: TextAlign.center, style: SgText.small),
              ),
            for (final p in store.mine) PostTile(post: p, onEdit: onEdit),
          ],
        );
      },
    );
  }
}

/// "팔로우까지 3일" with ten segments, one per writing day.
class FollowProgress extends StatelessWidget {
  const FollowProgress({super.key, required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    const total = PostStore.daysToFollow;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        border: Border.all(color: SgColors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('팔로우까지 ${total - days}일',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              Text('$days / $total',
                  style: SgText.mono.copyWith(fontSize: 13)),
            ],
          ),
          const SizedBox(height: 10),
          Semantics(
            label: '$total일 중 $days일 작성',
            child: Row(
              children: [
                for (var i = 0; i < total; i++)
                  Expanded(
                    child: Container(
                      height: 6,
                      margin: EdgeInsets.only(right: i == total - 1 ? 0 : 4),
                      decoration: BoxDecoration(
                        color: i < days ? SgColors.accent : SgColors.line,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Text('글을 쓴 날이 10일이 되면 팔로우가 열려요. 연속이 아니어도 돼요.',
              style: SgText.small),
        ],
      ),
    );
  }
}
