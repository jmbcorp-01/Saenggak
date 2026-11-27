import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:saenggak/api/backend.dart';
import 'package:saenggak/api/demo_backend.dart';
import 'package:saenggak/data/app_state.dart';
import 'package:saenggak/models/profile.dart';

/// Holds the profile until told, and notes when the feed is asked for.
class HeldProfileBackend extends DemoBackend {
  final profile = Completer<void>();
  bool feedAskedFirst = false;

  @override
  Future<Profile?> me() async {
    await profile.future;
    return super.me();
  }

  @override
  Future<FeedPage> feed({required String lang, bool following = false, String? authorId, String? before}) {
    if (!profile.isCompleted) feedAskedFirst = true;
    return super.feed(lang: lang, following: following, authorId: authorId, before: before);
  }
}

void main() {
  test('asks for the lists while the profile is still on its way', () async {
    final backend = HeldProfileBackend();
    final state = AppState(backend: backend);
    final loaded = state.start();
    await Future<void>.delayed(Duration.zero);
    expect(backend.feedAskedFirst, isTrue);
    backend.profile.complete();
    await loaded;
    expect(state.me, isNotNull);
    expect(state.feed, isNotEmpty);
    expect(state.loading, isFalse);
  });
}
