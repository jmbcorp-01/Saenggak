import 'package:material_ui/material_ui.dart';

import '../l10n/l10n.dart';
import '../theme/tokens.dart';

/// The ㅅ symbol: two brush strokes like a walking person, and a dot above
/// for a thought that has just come up. Drawn on a 64 x 64 grid.
class SymbolMark extends StatelessWidget {
  const SymbolMark({super.key, this.size = 30, this.strokeColor, this.dotColor, this.semanticLabel = '생각'});

  final double size;

  /// Defaults to the accent.
  final Color? strokeColor;

  /// Defaults to the ink color.
  final Color? dotColor;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final mark = CustomPaint(
      size: Size.square(size),
      painter: _SymbolPainter(strokeColor ?? SgColors.accent, dotColor ?? SgColors.ink),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: mark);
    return Semantics(label: t(semanticLabel!), image: true, child: mark);
  }
}

class _SymbolPainter extends CustomPainter {
  _SymbolPainter(this.stroke, this.dot);

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
    canvas.drawPath(
      Path()
        ..moveTo(34, 9)
        ..cubicTo(33, 27, 25, 43, 11, 55),
      pen,
    );
    canvas.drawPath(
      Path()
        ..moveTo(30.5, 30)
        ..cubicTo(36, 42, 45, 50, 54, 55),
      pen,
    );
    canvas.drawCircle(const Offset(47, 14), 3.4, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(_SymbolPainter old) => old.stroke != stroke || old.dot != dot;
}

/// The symbol drawn part way: the first stroke over the first 45% of
/// [progress], the second over the next 45%, then the dot. [dotLift] raises
/// the dot by up to 4 units of the 64 grid.
class SymbolStrokePainter extends CustomPainter {
  SymbolStrokePainter({required this.progress, required this.dotLift, required this.stroke, required this.dot});

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
  bool shouldRepaint(SymbolStrokePainter old) =>
      old.progress != progress || old.dotLift != dotLift || old.stroke != stroke || old.dot != dot;
}
