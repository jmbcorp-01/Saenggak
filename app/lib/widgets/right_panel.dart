import 'package:material_ui/material_ui.dart';

import '../core/links.dart';
import '../data/app_state.dart';
import '../models/post.dart';
import '../screens/profile_screen.dart' show FollowProgress;
import '../theme/tokens.dart';
import 'post_tile.dart' show Avatar, EmpathyIcon;
import 'pressable.dart';

/// The panel on the right of a wide screen: the reader's own writing so far,
/// the thoughts readers are 공감ing with most, and the site links.
class RightPanel extends StatelessWidget {
  const RightPanel({super.key, required this.state, required this.onOpenAuthor});

  final AppState state;
  final void Function(String userId) onOpenAuthor;

  static const width = 350.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final me = state.me;
          final now = state.clock();
          final popular = [
            for (final p in state.feed)
              if (!p.isMine && now.difference(p.createdAt) < const Duration(days: 2) && p.empathyCount > 0) p,
          ]..sort((a, b) => b.empathyCount.compareTo(a.empathyCount));
          final received = state.mine.fold<int>(0, (s, p) => s + p.empathyCount);
          return ListView(
            padding: const EdgeInsets.fromLTRB(SgSpace.xl, SgSpace.md, SgSpace.lg, SgSpace.xl),
            children: [
              if (me != null)
                _Card(
                  title: '나의 생각',
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(SgSpace.lg, 0, SgSpace.lg, SgSpace.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _Stat(value: '${me.writingDays}', label: '쓴 날'),
                            _Stat(value: '${state.mine.length}', label: '쓴 글'),
                            _Stat(value: '$received', label: '받은 공감'),
                          ],
                        ),
                        if (!me.followUnlocked) ...[
                          const SizedBox(height: SgSpace.md),
                          FollowProgress(days: me.writingDays, total: me.daysToFollow),
                        ],
                      ],
                    ),
                  ),
                ),
              if (popular.isNotEmpty) ...[
                const SizedBox(height: SgSpace.lg),
                _Card(
                  title: '많이 공감받은 생각',
                  child: Column(
                    children: [
                      for (final p in popular.take(4)) _PopularRow(post: p, onTap: () => onOpenAuthor(p.authorId)),
                      const SizedBox(height: SgSpace.sm),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: SgSpace.lg),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: SgSpace.lg),
                child: Wrap(
                  spacing: SgSpace.md,
                  runSpacing: SgSpace.xs,
                  children: [
                    _FooterLink('이용약관', () => openPage('terms.html')),
                    _FooterLink('개인정보 처리방침', () => openPage('privacy.html')),
                    _FooterLink('문의하기', () => openPage('support.html')),
                    Text('© ${now.year} 생각', style: SgText.small),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: SgColors.raised, borderRadius: BorderRadius.circular(SgRadius.lg)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(SgSpace.lg, SgSpace.md, SgSpace.lg, SgSpace.md),
            child: Text(title, style: SgText.title.copyWith(fontSize: 18)),
          ),
          child,
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: SgText.title.copyWith(fontSize: 22, fontFeatures: const [FontFeature.tabularFigures()])),
        Text(label, style: SgText.small),
      ],
    ),
  );
}

class _PopularRow extends StatelessWidget {
  const _PopularRow({required this.post, required this.onTap});

  final Post post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      semanticLabel: '${post.authorName}의 생각, 공감 ${post.empathyCount}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SgSpace.lg, vertical: SgSpace.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Avatar(initial: post.authorInitial, color: post.avatarColor, photoUrl: post.authorPhotoUrl, size: 32),
            const SizedBox(width: SgSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: post.authorName, style: SgText.name.copyWith(fontSize: 14)),
                        TextSpan(text: ' @${post.authorHandle}', style: SgText.small),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    post.translation ?? post.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SgText.body.copyWith(fontSize: 14, height: 1.5),
                  ),
                  const SizedBox(height: SgSpace.xs),
                  Row(
                    children: [
                      EmpathyIcon(active: post.empathizedByMe, color: SgColors.muted),
                      const SizedBox(width: SgSpace.xs),
                      Text('${post.empathyCount}', style: SgText.small),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FooterLink extends StatefulWidget {
  const _FooterLink(this.text, this.onTap);

  final String text;
  final VoidCallback onTap;

  @override
  State<_FooterLink> createState() => _FooterLinkState();
}

class _FooterLinkState extends State<_FooterLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: Text(widget.text, style: SgText.small.copyWith(decoration: _hover ? TextDecoration.underline : null)),
    ),
  );
}
