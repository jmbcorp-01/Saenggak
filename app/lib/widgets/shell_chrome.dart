import 'package:material_ui/material_ui.dart';

/// Whether the phone layout's header and bottom menu are showing. They slide
/// away while the reader scrolls down and come back on the way up.
class ShellChrome extends InheritedNotifier<ValueNotifier<bool>> {
  const ShellChrome({super.key, required ValueNotifier<bool> visible, required super.child}) : super(notifier: visible);

  /// True when there is no shell above, as in tests of a single screen.
  static bool visibleOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellChrome>()?.notifier?.value ?? true;

  /// Hides or shows the bars from a vertical scroll. Returns false so the
  /// notification keeps bubbling.
  static bool track(ValueNotifier<bool> visible, ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (n is ScrollUpdateNotification) {
      final delta = n.scrollDelta ?? 0;
      if (n.metrics.pixels <= 60) {
        visible.value = true;
      } else if (delta > 6) {
        visible.value = false;
      } else if (delta < -6) {
        visible.value = true;
      }
    }
    return false;
  }
}
