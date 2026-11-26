import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';

/// Fades and lifts [child] into place once, after [delay]. Used for posts
/// that have just arrived so they settle in rather than pop in.
class Appear extends StatefulWidget {
  const Appear({super.key, required this.child, this.delay = Duration.zero, this.enabled = true});

  final Widget child;
  final Duration delay;

  /// False shows the child at once.
  final bool enabled;

  @override
  State<Appear> createState() => _AppearState();
}

class _AppearState extends State<Appear> with SingleTickerProviderStateMixin {
  // The delay is the start of the animation's run rather than a timer, so
  // nothing is left waiting if the row goes away first.
  late final _c = AnimationController(
    vsync: this,
    duration: SgMotion.slow + widget.delay,
    value: widget.enabled ? 0 : 1,
  );
  late final _curve = CurvedAnimation(
    parent: _c,
    curve: Interval(
      widget.delay.inMicroseconds / (SgMotion.slow + widget.delay).inMicroseconds,
      1,
      curve: SgMotion.emphasized,
    ),
  );

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _c.forward();
  }

  @override
  void dispose() {
    _curve.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(_curve),
        child: widget.child,
      ),
    );
  }
}
