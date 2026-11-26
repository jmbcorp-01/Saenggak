import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';
import 'symbol_mark.dart';

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
              painter: SymbolStrokePainter(
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
