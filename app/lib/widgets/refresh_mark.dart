import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';

/// The ㅅ symbol drawn stroke by stroke as the reader pulls down, then
/// breathing while the feed reloads.
class RefreshMark extends StatefulWidget {
  const RefreshMark({super.key, required this.progress, required this.spinning, this.size = 30});

  /// 0 to 1: how far toward a refresh the pull has gone.
  final double progress;

  /// True while refreshing.
  final bool spinning;
  final double size;

  @override
  State<RefreshMark> createState() => _RefreshMarkState();
}

class _RefreshMarkState extends State<RefreshMark> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(RefreshMark old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.spinning && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.spinning && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.spinning ? '새로고침 중' : null,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final pulse = Curves.easeInOut.transform(_c.value);
          return Transform.scale(
            scale: 1 + 0.12 * pulse,
            child: CustomPaint(
              size: Size.square(widget.size),
              painter: _MarkPainter(
                progress: widget.spinning ? 1 : widget.progress,
                dotLift: widget.spinning ? pulse : 0,
                stroke: SgColors.accent,
                dot: SgColors.ink,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter({required this.progress, required this.dotLift, required this.stroke, required this.dot});

  final double progress;
  final double dotLift;
  final Color stroke;
  final Color dot;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 64, size.height / 64);
    final pen = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.5
      ..strokeCap = StrokeCap.round;
    final first = Path()
      ..moveTo(34, 9)
      ..cubicTo(33, 27, 25, 43, 11, 55);
    final second = Path()
      ..moveTo(30.5, 30)
      ..cubicTo(36, 42, 45, 50, 54, 55);
    // First stroke over the first 45% of the pull, the second over the next
    // 45%, then the dot.
    void partial(Path path, double t) {
      if (t <= 0) return;
      for (final m in path.computeMetrics()) {
        canvas.drawPath(m.extractPath(0, m.length * t.clamp(0.0, 1.0)), pen);
      }
    }

    partial(first, progress / 0.45);
    partial(second, (progress - 0.45) / 0.45);
    final d = ((progress - 0.9) / 0.1).clamp(0.0, 1.0);
    if (d > 0) {
      canvas.drawCircle(Offset(47, 14 - 4 * dotLift), 3.4 * d, Paint()..color = dot);
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.progress != progress || old.dotLift != dotLift || old.stroke != stroke || old.dot != dot;
}
