import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';

/// The ㅅ symbol: two brush strokes like a walking person, and a dot above
/// for a thought that has just come up. Drawn on a 64 x 64 grid.
class SymbolMark extends StatelessWidget {
  const SymbolMark({
    super.key,
    this.size = 30,
    this.strokeColor = SgColors.accent,
    this.dotColor = SgColors.ink,
    this.semanticLabel = '생각',
  });

  final double size;
  final Color strokeColor;
  final Color dotColor;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final mark = CustomPaint(
      size: Size.square(size),
      painter: _SymbolPainter(strokeColor, dotColor),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: mark);
    return Semantics(label: semanticLabel, image: true, child: mark);
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
  bool shouldRepaint(_SymbolPainter old) =>
      old.stroke != stroke || old.dot != dot;
}
