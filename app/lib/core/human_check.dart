import 'dart:math' as math;

import 'typing_session.dart';

/// Why a draft looks machine-entered.
enum HumanCheckIssue {
  /// Too few recorded changes for the length of the text.
  tooFewEvents,

  /// Characters arrived faster than a person can type.
  tooFast,

  /// Gaps between keys were almost perfectly even, like a script.
  tooRegular,
}

class HumanCheckResult {
  const HumanCheckResult(this.issues);

  final List<HumanCheckIssue> issues;

  bool get passed => issues.isEmpty;
}

/// A first, on-device check that a draft was typed by a person.
///
/// The server runs the same rules again on the recorded session before a
/// post is accepted, so this only gives the writer early feedback.
class HumanCheck {
  HumanCheck._();

  /// Keyboard changes needed per 10 characters typed on the keyboard.
  static const double minEventsPer10Chars = 4;

  /// Fastest sustained keyboard speed a person reaches, characters a second.
  static const double maxCharsPerSecond = 15;

  /// Below this coefficient of variation, key gaps are too even to be human.
  static const double minIntervalVariation = 0.15;

  /// Fewer intervals than this are not enough to judge rhythm.
  static const int minIntervalsForRhythm = 20;

  static HumanCheckResult evaluate(TypingSession session) {
    final issues = <HumanCheckIssue>[];
    final keyboardEvents = session.events.where((e) => e.source == InputSource.keyboard).toList();
    final keyboardChars = keyboardEvents.fold<int>(0, (sum, e) => sum + e.inserted);

    if (keyboardChars > 0 && keyboardEvents.length * 10 / keyboardChars < minEventsPer10Chars) {
      issues.add(HumanCheckIssue.tooFewEvents);
    }

    if (keyboardEvents.length >= 2) {
      final spanMs = keyboardEvents.last.atMs - keyboardEvents.first.atMs;
      final cps = spanMs == 0 ? double.infinity : keyboardChars * 1000 / spanMs;
      if (keyboardChars >= 20 && cps > maxCharsPerSecond) {
        issues.add(HumanCheckIssue.tooFast);
      }
    }

    final intervals = session.keyboardIntervals();
    if (intervals.length >= minIntervalsForRhythm) {
      final mean = intervals.reduce((a, b) => a + b) / intervals.length;
      final variance = intervals.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) / intervals.length;
      final cv = mean == 0 ? 0 : math.sqrt(variance) / mean;
      if (cv < minIntervalVariation) issues.add(HumanCheckIssue.tooRegular);
    }

    return HumanCheckResult(issues);
  }
}
