import 'package:material_ui/material_ui.dart';

import '../core/typing_session.dart';
import '../models/post.dart';
import '../theme/tokens.dart';

/// Round profile photo. Shows the author's initial until photos are wired up.
class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.initial,
    required this.color,
    this.size = 40,
    this.label,
  });

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
            style: TextStyle(
              color: fg,
              fontSize: size * 0.38,
              fontWeight: FontWeight.w500,
            ),
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
  Widget build(BuildContext context) => CustomPaint(
        size: const Size(20, 16),
        painter: _EmpathyPainter(active, color),
      );
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
      final overlap = Path.combine(
        PathOperation.intersect,
        Path()..addOval(left),
        Path()..addOval(right),
      );
      canvas.drawPath(overlap, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_EmpathyPainter old) =>
      old.active != active || old.color != color;
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
class PostTile extends StatelessWidget {
  const PostTile({
    super.key,
    required this.post,
    this.onEmpathy,
    this.onEdit,
  });

  final Post post;
  final VoidCallback? onEmpathy;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final active = post.empathizedByMe;
    final empathyColor = active ? SgColors.accentText : SgColors.muted;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: SgColors.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Avatar(
            initial: post.authorInitial,
            color: post.avatarColor,
            label: '${post.authorName} 프로필 사진',
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: post.authorName, style: SgText.name),
                          TextSpan(
                            text: ' @${post.authorHandle} · ${post.postedAgo}',
                            style: SgText.meta,
                          ),
                        ]),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (post.editable && onEdit != null)
                      TextButton(
                        onPressed: onEdit,
                        style: TextButton.styleFrom(
                          foregroundColor: SgColors.muted,
                          minimumSize: const Size(44, 32),
                        ),
                        child: const Text('수정'),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(post.body, style: SgText.body),
                if (post.translatedFrom != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text('${post.translatedFrom}에서 번역됨 · ',
                          style: SgText.small),
                      GestureDetector(
                        onTap: () {},
                        child: Text(
                          '원문 보기',
                          style: SgText.small.copyWith(
                            color: SgColors.accentText,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Semantics(
                      key: ValueKey('empathy-${post.id}'),
                      container: true,
                      button: true,
                      label: '공감 ${post.empathyCount}${active ? ', 공감함' : ''}',
                      child: ExcludeSemantics(
                        child: InkWell(
                          onTap: onEmpathy,
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
                                    fontWeight: active
                                        ? FontWeight.w500
                                        : FontWeight.w400,
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
