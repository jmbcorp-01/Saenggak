import 'package:material_ui/material_ui.dart';

import '../core/typing_session.dart';
import '../models/post.dart';
import '../theme/tokens.dart';

/// Round profile photo. Shows the author's initial until photos are wired up.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.initial, required this.color, this.size = 40, this.label});

  final String initial;
  final int color;
  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final bg = Color(color);
    final fg = bg.computeLuminance() > 0.4 ? SgColors.ink : Colors.white;
    return Semantics(
      label: label,
      image: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: ExcludeSemantics(
          child: Text(
            initial,
            style: TextStyle(color: fg, fontSize: size * 0.38, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }
}

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
      label: '직접 타이핑 $text',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.keyboard_outlined, size: 15, color: SgColors.muted),
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

  @override
  State<PostTile> createState() => _PostTileState();
}

class _PostTileState extends State<PostTile> {
  bool _showOriginal = false;

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final active = post.empathizedByMe;
    final empathyColor = active ? SgColors.accentText : SgColors.muted;
    final translated = post.translation != null && !_showOriginal;
    final ago = timeAgo(post.createdAt, widget.now ?? DateTime.now());
    final canEdit = post.editable && widget.onEdit != null;
    final canDelete = post.isMine && widget.onDelete != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: SgColors.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: widget.onOpenAuthor,
            child: Avatar(initial: post.authorInitial, color: post.avatarColor, label: '${post.authorName} 프로필 사진'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: GestureDetector(
                        onTap: widget.onOpenAuthor,
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: post.authorName, style: SgText.name),
                              TextSpan(
                                text: ' @${post.authorHandle} · $ago${post.editedAt != null ? ' · 수정됨' : ''}',
                                style: SgText.meta,
                              ),
                            ],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (canEdit || canDelete)
                      PopupMenuButton<String>(
                        key: ValueKey('menu-${post.id}'),
                        tooltip: '더보기',
                        iconSize: 18,
                        icon: const Icon(Icons.more_horiz, color: SgColors.muted),
                        onSelected: (v) => v == 'edit' ? widget.onEdit!() : widget.onDelete!(),
                        itemBuilder: (_) => [
                          if (canEdit) const PopupMenuItem(value: 'edit', child: Text('수정')),
                          if (canDelete)
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('삭제', style: TextStyle(color: SgColors.accentText)),
                            ),
                        ],
                      )
                    else
                      const SizedBox(height: 40),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(translated ? post.translation! : post.body, style: SgText.body),
                ),
                if (post.translation != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(translated ? '${languageName(post.lang)}에서 번역됨 · ' : '원문 · ', style: SgText.small),
                      GestureDetector(
                        onTap: () => setState(() => _showOriginal = !_showOriginal),
                        child: Text(
                          translated ? '원문 보기' : '번역 보기',
                          style: SgText.small.copyWith(color: SgColors.accentText, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Semantics(
                        key: ValueKey('empathy-${post.id}'),
                        container: true,
                        button: !post.isMine,
                        label: '공감 ${post.empathyCount}${active ? ', 공감함' : ''}',
                        child: ExcludeSemantics(
                          child: InkWell(
                            onTap: post.isMine ? null : widget.onEmpathy,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 44),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  EmpathyIcon(active: active, color: empathyColor),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${post.empathyCount}',
                                    style: SgText.small.copyWith(
                                      color: empathyColor,
                                      fontWeight: active ? FontWeight.w500 : FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
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
    );
  }
}
