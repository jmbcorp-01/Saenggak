import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:saenggak/api/backend.dart';
import 'package:saenggak/api/demo_backend.dart';
import 'package:saenggak/data/app_state.dart';
import 'package:saenggak/models/post.dart';
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

  profileChanges();
}

void profileChanges() {
  test('a profile change shows on the reader\'s posts already loaded', () async {
    final state = AppState(backend: DemoBackend());
    await state.start();
    final myId = state.me!.id;
    final mine = Post(
      id: 'p-mine',
      authorId: myId,
      authorName: state.me!.displayName,
      authorHandle: state.me!.handle,
      body: 'body',
      lang: 'ko',
      createdAt: DateTime.utc(2026, 11, 27),
      typingTime: const Duration(seconds: 30),
      empathyCount: 0,
      isMine: true,
    );
    state.mine = [mine];
    state.feed = [mine, ...state.feed];
    await state.saveProfile(handle: state.me!.handle, displayName: '새 이름', bio: '');
    expect(state.mine.single.authorName, '새 이름');
    expect(state.feed.first.authorName, '새 이름');
    expect([...state.feed, ...state.mine].where((p) => p.authorId != myId && p.authorName == '새 이름'), isEmpty);
  });
}
