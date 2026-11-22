/// Where a change to the draft came from.
enum InputSource { keyboard, voice }

/// One accepted change to the draft.
class TypingEvent {
  const TypingEvent({
    required this.atMs,
    required this.inserted,
    required this.deleted,
    required this.source,
  });

  /// Milliseconds since the session started.
  final int atMs;

  /// Characters added by this change.
  final int inserted;

  /// Characters removed by this change.
  final int deleted;

  final InputSource source;

  Map<String, Object> toJson() => {
        't': atMs,
        'i': inserted,
        'd': deleted,
        's': source.name,
      };
}

/// Records how a draft was typed, so the server can check that a person wrote
/// it and so the post can show its real typing time.
///
/// Only timings and character counts are kept, never the keys themselves.
class TypingSession {
  TypingSession({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  /// Pauses longer than this are thinking time, not typing time.
  static const Duration idleCutoff = Duration(seconds: 30);

  final DateTime Function() _clock;
  DateTime? _startedAt;
  final List<TypingEvent> _events = [];
  int _rejectedPastes = 0;

  List<TypingEvent> get events => List.unmodifiable(_events);

  /// How many times a paste or other bulk insert was blocked.
  int get rejectedPastes => _rejectedPastes;

  void record({
    required int inserted,
    required int deleted,
    InputSource source = InputSource.keyboard,
  }) {
    if (inserted == 0 && deleted == 0) return;
    final now = _clock();
    _startedAt ??= now;
    _events.add(TypingEvent(
      atMs: now.difference(_startedAt!).inMilliseconds,
      inserted: inserted,
      deleted: deleted,
      source: source,
    ));
  }

  void recordRejectedPaste() => _rejectedPastes++;

  /// Time spent actually typing: the gaps between changes, leaving out
  /// pauses longer than [idleCutoff].
  Duration get activeDuration {
    var ms = 0;
    for (var i = 1; i < _events.length; i++) {
      final gap = _events[i].atMs - _events[i - 1].atMs;
      if (gap <= idleCutoff.inMilliseconds) ms += gap;
    }
    return Duration(milliseconds: ms);
  }

  /// Keyboard-only gaps between consecutive insertions, in milliseconds.
  List<int> keyboardIntervals() {
    final out = <int>[];
    for (var i = 1; i < _events.length; i++) {
      final a = _events[i - 1];
      final b = _events[i];
      if (a.source == InputSource.keyboard &&
          b.source == InputSource.keyboard &&
          b.inserted > 0) {
        out.add(b.atMs - a.atMs);
      }
    }
    return out;
  }

  Map<String, Object> toJson() => {
        'events': _events.map((e) => e.toJson()).toList(),
        'rejectedPastes': _rejectedPastes,
        'activeMs': activeDuration.inMilliseconds,
      };

  void reset() {
    _startedAt = null;
    _events.clear();
    _rejectedPastes = 0;
  }
}

/// Formats a typing duration the way posts show it, for example "2분 18초".
String formatTypingDuration(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds % 60;
  final ss = seconds.toString().padLeft(2, '0');
  if (minutes == 0) return '$seconds초';
  return '$minutes분 $ss초';
}
