import 'package:flutter/services.dart';

import 'typing_session.dart';

/// Lets only hand-typed changes into the draft and records each one.
///
/// A change that inserts more than [maxKeyboardChunk] characters at once is
/// treated as a paste and rejected, unless voice input is on. Korean, Japanese
/// and Chinese input methods send one composed character at a time, so the
/// limit leaves them room while stopping a pasted sentence.
class HumanInputFormatter extends TextInputFormatter {
  HumanInputFormatter({
    required this.session,
    required this.isVoiceActive,
    this.onRejected,
  });

  static const int maxKeyboardChunk = 4;

  final TypingSession session;
  final bool Function() isVoiceActive;
  final void Function()? onRejected;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final change = diff(oldValue.text, newValue.text);
    final voice = isVoiceActive();

    if (!voice && change.inserted > maxKeyboardChunk) {
      session.recordRejectedPaste();
      onRejected?.call();
      return oldValue;
    }

    session.record(
      inserted: change.inserted,
      deleted: change.deleted,
      source: voice ? InputSource.voice : InputSource.keyboard,
    );
    return newValue;
  }

  /// Characters inserted and deleted between [before] and [after], found by
  /// trimming their common start and end.
  static ({int inserted, int deleted}) diff(String before, String after) {
    final a = before.runes.toList();
    final b = after.runes.toList();
    var start = 0;
    while (start < a.length && start < b.length && a[start] == b[start]) {
      start++;
    }
    var endA = a.length;
    var endB = b.length;
    while (endA > start && endB > start && a[endA - 1] == b[endB - 1]) {
      endA--;
      endB--;
    }
    return (inserted: endB - start, deleted: endA - start);
  }
}
