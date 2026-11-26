import 'package:material_ui/material_ui.dart';

/// Closes the on-screen keyboard.
void hideKeyboard() => FocusManager.instance.primaryFocus?.unfocus();

/// Closes the keyboard when the reader taps anywhere that is not a field or
/// a button. iOS has no back key, and its number pad and multi-line fields
/// have no key that closes the keyboard, so without this a field can trap it.
class TapToHideKeyboard extends StatelessWidget {
  const TapToHideKeyboard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Translucent so the tap still reaches what is underneath; a field or
    // button that takes the tap wins the gesture and the keyboard stays.
    return GestureDetector(behavior: HitTestBehavior.translucent, onTap: hideKeyboard, child: child);
  }
}
