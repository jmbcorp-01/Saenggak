import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';

/// Opens [builder] as a page in the current column. On a computer that keeps
/// the side menus in place, as the timeline does.
Future<T?> pushPage<T>(BuildContext context, WidgetBuilder builder) =>
    Navigator.of(context).push<T>(MaterialPageRoute<T>(builder: builder));

/// Opens a task that takes over the screen, such as writing a post: it rises
/// from the bottom on a phone and opens as a centered window on a wider
/// screen.
Future<T?> pushModal<T>(BuildContext context, WidgetBuilder builder, {double maxHeight = 560}) =>
    Navigator.of(context, rootNavigator: true).push<T>(modalRoute<T>(context, builder, maxHeight: maxHeight));

/// The route [pushModal] uses, for replacing one modal task with the next.
Route<T> modalRoute<T>(BuildContext context, WidgetBuilder builder, {double maxHeight = 560}) {
  final wide = MediaQuery.sizeOf(context).width >= SgBreakpoints.rail;
  if (!wide) return _RiseRoute<T>(builder: builder);
  return RawDialogRoute<T>(
    barrierDismissible: true,
    barrierLabel: '닫기',
    barrierColor: Colors.black.withValues(alpha: SgColors.isDark ? 0.6 : 0.4),
    transitionDuration: SgMotion.medium,
    pageBuilder: (context, _, _) => SafeArea(
      child: Align(
        alignment: const Alignment(0, -0.6),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: SgBreakpoints.column, maxHeight: maxHeight),
          child: Padding(
            padding: const EdgeInsets.all(SgSpace.lg),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(SgRadius.lg),
              child: Builder(builder: builder),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: SgMotion.ease, reverseCurve: Curves.easeIn);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(curved), child: child),
      );
    },
  );
}

/// A full-screen page that slides up from the bottom and back down.
class _RiseRoute<T> extends PageRoute<T> {
  _RiseRoute({required this.builder}) : super(fullscreenDialog: true);

  final WidgetBuilder builder;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  bool get opaque => true;

  @override
  Duration get transitionDuration => SgMotion.slow;

  @override
  Duration get reverseTransitionDuration => SgMotion.medium;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) =>
      builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: SgMotion.emphasized, reverseCurve: Curves.easeInCubic);
    return SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(curved),
      child: child,
    );
  }
}
