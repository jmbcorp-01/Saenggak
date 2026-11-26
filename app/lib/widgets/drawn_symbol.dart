import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';
import 'symbol_mark.dart';

/// The symbol written stroke by stroke when it first appears, as if by hand,
/// with the dot set down last. The dot then rises and settles a few times,
/// like a thought coming up.
class DrawnSymbol extends StatefulWidget {
  const DrawnSymbol({super.key, required this.size, this.delay = Duration.zero, this.breaths = 8});

  final double size;
  final Duration delay;

  /// How many times the dot rises before it rests.
  final int breaths;

  @override
  State<DrawnSymbol> createState() => _DrawnSymbolState();
}

class _DrawnSymbolState extends State<DrawnSymbol> with TickerProviderStateMixin {
  static const _drawTime = Duration(milliseconds: 1500);

  // The delay is part of the run, so no timer is left behind.
  late final _draw = AnimationController(vsync: this, duration: widget.delay + _drawTime);
  late final _progress = CurvedAnimation(
    parent: _draw,
    curve: Interval(
      widget.delay.inMicroseconds / (widget.delay + _drawTime).inMicroseconds,
      1,
      curve: Curves.easeInOutCubic,
    ),
  );
  late final _breath = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  int _breathsLeft = 0;

  @override
  void initState() {
    super.initState();
    _breathsLeft = widget.breaths * 2;
    _breath.addStatusListener((s) {
      if (s != AnimationStatus.completed && s != AnimationStatus.dismissed) return;
      if (--_breathsLeft <= 0) return;
      s == AnimationStatus.completed ? _breath.reverse() : _breath.forward();
    });
    _draw.forward().then((_) {
      if (mounted && widget.breaths > 0) _breath.forward();
    });
  }

  @override
  void dispose() {
    _progress.dispose();
    _draw.dispose();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: '생각',
      image: true,
      child: AnimatedBuilder(
        animation: Listenable.merge([_progress, _breath]),
        builder: (context, _) => CustomPaint(
          size: Size.square(widget.size),
          painter: SymbolStrokePainter(
            progress: still ? 1 : _progress.value,
            dotLift: still ? 0 : Curves.easeInOutSine.transform(_breath.value),
            stroke: SgColors.accent,
            dot: SgColors.ink,
          ),
        ),
      ),
    );
  }
}

/// Tracks the mouse anywhere over [child], for [LeanToMouse] widgets inside.
class MouseArea extends StatefulWidget {
  const MouseArea({super.key, required this.child});

  final Widget child;

  @override
  State<MouseArea> createState() => _MouseAreaState();
}

class _MouseAreaState extends State<MouseArea> {
  /// -1 to 1 across and down the area; zero when the mouse is away.
  final _at = ValueNotifier(Offset.zero);

  @override
  void dispose() {
    _at.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (e) {
        final size = context.size;
        if (size == null || size.isEmpty) return;
        _at.value = Offset(
          (e.localPosition.dx / size.width * 2 - 1).clamp(-1.0, 1.0),
          (e.localPosition.dy / size.height * 2 - 1).clamp(-1.0, 1.0),
        );
      },
      onExit: (_) => _at.value = Offset.zero,
      child: _MouseAt(at: _at, child: widget.child),
    );
  }
}

class _MouseAt extends InheritedWidget {
  const _MouseAt({required this.at, required super.child});

  final ValueNotifier<Offset> at;

  @override
  bool updateShouldNotify(_MouseAt old) => old.at != at;
}

/// Moves and turns [child] a little toward the mouse, easing after it.
class LeanToMouse extends StatelessWidget {
  const LeanToMouse({super.key, required this.child, this.shift = 18, this.tilt = 0.05});

  final Widget child;

  /// Most it moves, in pixels, and turns, in radians, at the area's edge.
  final double shift;
  final double tilt;

  @override
  Widget build(BuildContext context) {
    final at = context.dependOnInheritedWidgetOfExactType<_MouseAt>()?.at;
    if (at == null) return child;
    return ValueListenableBuilder(
      valueListenable: at,
      builder: (context, target, child) => TweenAnimationBuilder<Offset>(
        tween: Tween(end: target),
        duration: const Duration(milliseconds: 800),
        curve: SgMotion.ease,
        builder: (context, p, child) => Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..translateByDouble(p.dx * shift, p.dy * shift * 0.6, 0, 1)
            ..rotateZ(p.dx * tilt),
          child: child,
        ),
        child: child,
      ),
      child: child,
    );
  }
}

/// Grows a button a touch under the mouse.
class HoverLift extends StatefulWidget {
  const HoverLift({super.key, required this.child});

  final Widget child;

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: AnimatedScale(
      scale: _hover ? 1.02 : 1,
      duration: SgMotion.medium,
      curve: SgMotion.ease,
      child: widget.child,
    ),
  );
}
