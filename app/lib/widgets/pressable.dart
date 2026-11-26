import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';

/// A surface that answers the pointer: a soft background under the mouse, a
/// deeper one while pressed, and a slight shrink for small targets. Used for
/// timeline rows, menu items and panel entries in place of ripples.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius = BorderRadius.zero,
    this.pressScale = 1.0,
    this.hoverColor,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Gives a firm tick on phones before it runs.
  final VoidCallback? onLongPress;
  final BorderRadius borderRadius;

  /// Below 1 for buttons and icons, which shrink a little while held.
  final double pressScale;
  final Color? hoverColor;
  final String? semanticLabel;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _hover = false;
  bool _down = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  void _setDown(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final color = !_enabled
        ? Colors.transparent
        : _down
        ? SgColors.pressed
        : _hover
        ? (widget.hoverColor ?? SgColors.hover)
        : Colors.transparent;
    Widget child = AnimatedContainer(
      duration: SgMotion.fast,
      curve: SgMotion.ease,
      decoration: BoxDecoration(color: color, borderRadius: widget.borderRadius),
      child: widget.child,
    );
    if (widget.pressScale != 1.0) {
      child = AnimatedScale(
        scale: _down ? widget.pressScale : 1.0,
        duration: SgMotion.fast,
        curve: SgMotion.ease,
        child: child,
      );
    }
    return Semantics(
      button: widget.onTap != null && widget.semanticLabel != null,
      label: widget.semanticLabel,
      child: MouseRegion(
        cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() {
          _hover = false;
          _down = false;
        }),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: widget.onTap == null ? null : (_) => _setDown(true),
          onTapUp: widget.onTap == null ? null : (_) => _setDown(false),
          onTapCancel: () => _setDown(false),
          onTap: widget.onTap,
          onLongPress: widget.onLongPress == null
              ? null
              : () {
                  _setDown(false);
                  HapticFeedback.mediumImpact();
                  widget.onLongPress!();
                },
          child: child,
        ),
      ),
    );
  }
}
