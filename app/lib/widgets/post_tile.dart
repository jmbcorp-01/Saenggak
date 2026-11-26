import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/typing_session.dart';
import '../l10n/l10n.dart';
import '../models/post.dart';
import '../theme/tokens.dart';
import 'pressable.dart';
import 'post_body.dart';

/// Round profile photo. Shows the initial on a colored circle when there is
/// no photo, or while it loads, or if it fails to load.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.initial, required this.color, this.size = 40, this.label, this.photoUrl});

  final String initial;
  final String? photoUrl;
  final int color;
  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final bg = Color(color);
    final fg = bg.computeLuminance() > 0.4 ? const Color(0xFF151515) : Colors.white;
    final letter = Text(
      initial,
      style: TextStyle(color: fg, fontSize: size * 0.38, fontWeight: FontWeight.w500),
    );
    return Semantics(
      label: label,
      image: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        clipBehavior: Clip.antiAlias,
        child: ExcludeSemantics(
          child: photoUrl == null
              ? letter
              : Image(
                  image: ResizeImage(
                    _provider(photoUrl!),
                    width: (size * MediaQuery.devicePixelRatioOf(context)).round(),
                  ),
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  frameBuilder: (context, child, frame, sync) => frame == null && !sync ? letter : child,
                  errorBuilder: (context, error, stack) => letter,
                ),
        ),
      ),
    );
  }
}

/// Photos from the server are URLs; the demo backend keeps them as data URLs.
ImageProvider _provider(String url) =>
    url.startsWith('data:') ? MemoryImage(UriData.parse(url).contentAsBytes()) : NetworkImage(url);

/// Two overlapping circles. The overlap fills in when the reader empathized.
class EmpathyIcon extends StatelessWidget {
  const EmpathyIcon({super.key, required this.active, required this.color});

  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(size: const Size(20, 16), painter: _EmpathyPainter(active, color));
}

class _EmpathyPainter extends CustomPainter {
  _EmpathyPainter(this.active, this.color);

  final bool active;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final left = Rect.fromCircle(center: const Offset(7, 8), radius: 6);
    final right = Rect.fromCircle(center: const Offset(13, 8), radius: 6);
    canvas.drawOval(left, pen);
    canvas.drawOval(right, pen);
    if (active) {
      final overlap = Path.combine(PathOperation.intersect, Path()..addOval(left), Path()..addOval(right));
      canvas.drawPath(overlap, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_EmpathyPainter old) => old.active != active || old.color != color;
}

/// "2분 18초" with a keyboard icon: how long the author typed.
class TypingTimeLabel extends StatelessWidget {
  const TypingTimeLabel({super.key, required this.duration});

  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final text = formatTypingDuration(duration);
    return Semantics(
      label: t('직접 타이핑 {0}', [text]),
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(SgIcons.keyboard, size: 15, color: SgColors.muted),
            const SizedBox(width: 5),
            Text(text, style: SgText.mono),
          ],
        ),
      ),
    );
  }
}

/// One post in a list, laid out like a familiar timeline row.
class PostTile extends StatefulWidget {
  const PostTile({
    super.key,
    required this.post,
    this.now,
    this.onEmpathy,
    this.onOpenAuthor,
    this.onEdit,
    this.onDelete,
    this.onAdminRemove,
    this.onReport,
    this.onBlock,
    this.onBookmark,
    this.onCopyLink,
  });

  final Post post;

  /// For "3시간" style times; defaults to the current time.
  final DateTime? now;
  final VoidCallback? onEmpathy;
  final VoidCallback? onOpenAuthor;

  /// Shown on the reader's own posts until the first 공감.
  final VoidCallback? onEdit;

  /// Shown on the reader's own posts.
  final VoidCallback? onDelete;

  /// Shown to admins on other people's posts.
  final VoidCallback? onAdminRemove;

  /// Shown on other people's posts.
  final VoidCallback? onReport;
  final VoidCallback? onBlock;

  /// Saves the post to read again, or takes it off the saved list.
  final VoidCallback? onBookmark;
  final VoidCallback? onCopyLink;

  @override
  State<PostTile> createState() => _PostTileState();
}

class _PostTileState extends State<PostTile> {
  bool _showOriginal = false;

  /// The actions open to this reader, for the "..." menu and the long-press
  /// sheet alike.
  List<({String value, String label, bool danger})> _actions() {
    final post = widget.post;
    return [
      if (widget.onBookmark != null) (value: 'bookmark', label: post.bookmarked ? t('저장 취소') : t('저장'), danger: false),
      if (widget.onCopyLink != null) (value: 'link', label: t('링크 복사'), danger: false),
      if (!post.isMine && widget.onReport != null) (value: 'report', label: t('신고'), danger: false),
      if (!post.isMine && widget.onBlock != null)
        (value: 'block', label: t('@{0} 차단', [post.authorHandle]), danger: false),
      if (!post.isMine && widget.onAdminRemove != null) (value: 'admin-remove', label: t('관리자: 글 내리기'), danger: true),
      if (post.editable && widget.onEdit != null) (value: 'edit', label: t('수정'), danger: false),
      if (post.isMine && widget.onDelete != null) (value: 'delete', label: t('삭제'), danger: true),
    ];
  }

  void _run(String value) => switch (value) {
    'edit' => widget.onEdit!(),
    'delete' => widget.onDelete!(),
    'report' => widget.onReport!(),
    'block' => widget.onBlock!(),
    'bookmark' => widget.onBookmark!(),
    'link' => widget.onCopyLink!(),
    _ => widget.onAdminRemove!(),
  };

  /// Long press on a phone: the same actions in a sheet from the bottom.
  Future<void> _openSheet() async {
    final actions = _actions();
    final picked = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final a in actions)
              ListTile(
                title: Text(a.label, style: TextStyle(color: a.danger ? SgColors.accentText : SgColors.ink)),
                onTap: () => Navigator.pop(context, a.value),
              ),
            const SizedBox(height: SgSpace.sm),
          ],
        ),
      ),
    );
    if (picked != null && mounted) _run(picked);
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final translated = post.translation != null && !_showOriginal;
    final ago = timeAgo(post.createdAt, widget.now ?? DateTime.now());
    final actions = _actions();

    return Pressable(
      onLongPress: actions.isEmpty ? null : _openSheet,
      child: Container(
        padding: const EdgeInsets.fromLTRB(SgSpace.lg, SgSpace.sm, SgSpace.sm, SgSpace.xs),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: SgColors.line)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The name beside it is the labelled way to the profile; the photo is
            // a second place to tap and is left out of the screen reader.
            ExcludeSemantics(
              child: MouseRegion(
                cursor: widget.onOpenAuthor != null ? SystemMouseCursors.click : MouseCursor.defer,
                child: GestureDetector(
                  onTap: widget.onOpenAuthor,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Avatar(initial: post.authorInitial, color: post.avatarColor, photoUrl: post.authorPhotoUrl),
                  ),
                ),
              ),
            ),
            const SizedBox(width: SgSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          button: widget.onOpenAuthor != null,
                          child: _AuthorLine(
                            name: post.authorName,
                            rest: ' @${post.authorHandle} · $ago${post.editedAt != null ? t(' · 수정됨') : ''}',
                            onTap: widget.onOpenAuthor,
                          ),
                        ),
                      ),
                      if (actions.isNotEmpty)
                        PopupMenuButton<String>(
                          key: ValueKey('menu-${post.id}'),
                          tooltip: t('더보기'),
                          iconSize: 18,
                          icon: Icon(SgIcons.more, color: SgColors.muted),
                          onSelected: _run,
                          itemBuilder: (_) => [
                            for (final a in actions)
                              PopupMenuItem(
                                value: a.value,
                                child: Text(a.label, style: a.danger ? TextStyle(color: SgColors.accentText) : null),
                              ),
                          ],
                        )
                      else
                        const SizedBox(height: 48),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: SgSpace.sm),
                    child: AnimatedSize(
                      duration: SgMotion.medium,
                      curve: SgMotion.ease,
                      alignment: Alignment.topLeft,
                      child: AnimatedSwitcher(
                        duration: SgMotion.medium,
                        layoutBuilder: (current, previous) =>
                            Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
                        child: PostBody(
                          translated ? post.translation! : post.body,
                          key: ValueKey(translated),
                          style: SgText.body,
                        ),
                      ),
                    ),
                  ),
                  if (post.translation != null)
                    Row(
                      children: [
                        Text(
                          translated ? t('{0}에서 번역됨 · ', [languageName(post.lang)]) : t('원문 · '),
                          style: SgText.small,
                        ),
                        TextButton(
                          onPressed: () => setState(() => _showOriginal = !_showOriginal),
                          style: TextButton.styleFrom(
                            foregroundColor: SgColors.accentText,
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            minimumSize: const Size(48, 44),
                            textStyle: SgText.label(size: 13, weight: FontWeight.w500),
                          ),
                          child: Text(translated ? t('원문 보기') : t('번역 보기')),
                        ),
                      ],
                    ),
                  Padding(
                    padding: const EdgeInsets.only(right: SgSpace.sm),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // The hover circle reaches past the text edge so the icon lines up with it.
                        Transform.translate(
                          offset: const Offset(-6, 0),
                          child: EmpathyButton(
                            key: ValueKey('empathy-${post.id}'),
                            active: post.empathizedByMe,
                            count: post.empathyCount,
                            onTap: post.isMine ? null : widget.onEmpathy,
                          ),
                        ),
                        TypingTimeLabel(duration: post.typingTime),
                      ],
                    ),
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

/// "이름 @handle · 3시간". The name underlines under the mouse, as a link.
class _AuthorLine extends StatefulWidget {
  const _AuthorLine({required this.name, required this.rest, this.onTap});

  final String name;
  final String rest;
  final VoidCallback? onTap;

  @override
  State<_AuthorLine> createState() => _AuthorLineState();
}

class _AuthorLineState extends State<_AuthorLine> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    // Only the text itself is the link, not the empty space after it.
    return Align(
      alignment: Alignment.centerLeft,
      child: MouseRegion(
        cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: 1,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: widget.name,
                      style: SgText.name.copyWith(
                        decoration: _hover && widget.onTap != null ? TextDecoration.underline : null,
                      ),
                    ),
                    TextSpan(text: widget.rest, style: SgText.meta),
                  ],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The 공감 button. Turning it on pops the icon, fills it, and rolls the
/// count up; turning it off rolls the count down.
class EmpathyButton extends StatefulWidget {
  const EmpathyButton({super.key, required this.active, required this.count, this.onTap});

  final bool active;
  final int count;

  /// Null on the reader's own posts, which cannot be 공감ed.
  final VoidCallback? onTap;

  @override
  State<EmpathyButton> createState() => _EmpathyButtonState();
}

class _EmpathyButtonState extends State<EmpathyButton> with SingleTickerProviderStateMixin {
  late final _pop = AnimationController(vsync: this, duration: const Duration(milliseconds: 360));
  late final _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.32).chain(CurveTween(curve: Curves.easeOut)), weight: 40),
    TweenSequenceItem(tween: Tween(begin: 1.32, end: 1.0).chain(CurveTween(curve: Curves.elasticOut)), weight: 60),
  ]).animate(_pop);
  bool _hover = false;
  int _direction = 1;

  @override
  void didUpdateWidget(EmpathyButton old) {
    super.didUpdateWidget(old);
    if (old.count != widget.count) _direction = widget.count > old.count ? 1 : -1;
    if (widget.active && !old.active) _pop.forward(from: 0);
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  void _tap() {
    if (!widget.active) HapticFeedback.lightImpact();
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final color = active || (_hover && widget.onTap != null) ? SgColors.accentText : SgColors.muted;
    return Semantics(
      container: true,
      button: widget.onTap != null,
      label: t('공감 {0}{1}', [widget.count, active ? t(', 공감함') : '']),
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap == null ? null : _tap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // A soft accent circle behind the icon under the mouse.
                  AnimatedContainer(
                    duration: SgMotion.fast,
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _hover && widget.onTap != null
                          ? SgColors.accent.withValues(alpha: 0.1)
                          : SgColors.accent.withValues(alpha: 0),
                    ),
                    child: ScaleTransition(
                      scale: _scale,
                      child: EmpathyIcon(active: active, color: color),
                    ),
                  ),
                  const SizedBox(width: 2),
                  ClipRect(
                    child: AnimatedSwitcher(
                      duration: SgMotion.medium,
                      switchInCurve: SgMotion.ease,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) {
                        final incoming = child.key == ValueKey(widget.count);
                        final from = Offset(0, incoming ? 0.8 * _direction : -0.8 * _direction);
                        return SlideTransition(
                          position: Tween(begin: from, end: Offset.zero).animate(animation),
                          child: FadeTransition(opacity: animation, child: child),
                        );
                      },
                      child: Text(
                        '${widget.count}',
                        key: ValueKey(widget.count),
                        style: SgText.small.copyWith(
                          color: color,
                          fontWeight: active ? FontWeight.w500 : FontWeight.w400,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
