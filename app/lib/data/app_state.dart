import 'package:material_ui/material_ui.dart';

import '../api/backend.dart';
import '../core/typing_session.dart';
import '../models/post.dart';
import '../models/profile.dart';
import '../models/publish_outcome.dart';

/// The signed-in user's profile and the lists the screens show, kept in step
/// with the server after each change.
class AppState extends ChangeNotifier {
  AppState({required this.backend, DateTime Function()? clock}) : clock = clock ?? DateTime.now;

  final Backend backend;
  final DateTime Function() clock;

  Profile? me;
  List<Post> feed = const [];
  List<Post> following = const [];
  List<Post> mine = const [];
  String? _feedNext;
  bool loading = false;
  String? error;

  /// Feed translations go into the reader's language.
  String get lang => me?.locale ?? 'ko';
  bool get hasMore => _feedNext != null;

  /// Loads the profile and the first page of each list.
  Future<void> start() async {
    me = await backend.me();
    notifyListeners();
    await refresh();
  }

  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final unlocked = me?.followUnlocked ?? false;
      final results = await Future.wait([
        backend.feed(lang: lang),
        if (unlocked) backend.feed(lang: lang, following: true),
        if (me != null) backend.feed(lang: lang, authorId: me!.id),
      ]);
      feed = results[0].items;
      _feedNext = results[0].next;
      var k = 1;
      following = unlocked ? results[k++].items : const [];
      mine = me != null ? results[k].items : const [];
    } catch (_) {
      error = '글을 불러오지 못했어요. 당겨서 다시 시도해주세요.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    final before = _feedNext;
    if (before == null || loading) return;
    loading = true;
    notifyListeners();
    try {
      final page = await backend.feed(lang: lang, before: before);
      feed = [...feed, ...page.items];
      _feedNext = page.next;
    } catch (_) {
      error = '글을 더 불러오지 못했어요.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void _replace(String id, Post Function(Post) change) {
    List<Post> apply(List<Post> list) => [for (final p in list) p.id == id ? change(p) : p];
    feed = apply(feed);
    following = apply(following);
    mine = apply(mine);
    notifyListeners();
  }

  /// Updates the count right away, then takes the server's numbers.
  Future<void> toggleEmpathy(Post post) async {
    if (post.isMine) return;
    final was = post.empathizedByMe;
    _replace(post.id, (p) => p.copyWith(empathizedByMe: !was, empathyCount: p.empathyCount + (was ? -1 : 1)));
    try {
      final r = await backend.toggleEmpathy(post.id);
      _replace(post.id, (p) => p.copyWith(empathizedByMe: r.empathized, empathyCount: r.count));
    } catch (_) {
      _replace(post.id, (p) => p.copyWith(empathizedByMe: was, empathyCount: post.empathyCount));
    }
  }

  Future<PublishOutcome> publish(String text, TypingSession session) async {
    final outcome = await backend.publish(text: text, session: session, localDate: localDateOf(clock()));
    await _afterWrite(outcome);
    return outcome;
  }

  Future<PublishOutcome> edit(Post post, String text, TypingSession session) async {
    final outcome = await backend.edit(post.id, text: text, session: session, localDate: localDateOf(clock()));
    await _afterWrite(outcome);
    return outcome;
  }

  Future<void> _afterWrite(PublishOutcome outcome) async {
    // A blocked post can take follow permission away, so refresh then too.
    if (outcome is Rejected && outcome.reason != RejectReason.blocked) return;
    try {
      me = await backend.me();
    } catch (_) {
      // The post went through; the lists catch up on the next refresh.
    }
    await refresh();
  }

  Future<void> delete(Post post) async {
    await backend.delete(post.id);
    feed = feed.where((p) => p.id != post.id).toList();
    following = following.where((p) => p.id != post.id).toList();
    mine = mine.where((p) => p.id != post.id).toList();
    me = await backend.me();
    notifyListeners();
  }

  Future<void> saveProfile({required String handle, required String displayName, String bio = ''}) async {
    me = await backend.saveProfile(
      handle: handle,
      displayName: displayName,
      bio: bio,
      locale: me?.locale ?? 'ko',
      timeZone: me?.timeZone ?? 'Asia/Seoul',
    );
    notifyListeners();
  }

  /// Follows or unfollows and returns the updated profile.
  Future<Profile> setFollowing(Profile user, bool follow) async {
    if (follow) {
      await backend.follow(user.id);
    } else {
      await backend.unfollow(user.id);
    }
    final updated = await backend.user(user.id);
    me = await backend.me();
    if (me?.followUnlocked ?? false) {
      following = (await backend.feed(lang: lang, following: true)).items;
    }
    notifyListeners();
    return updated;
  }
}
