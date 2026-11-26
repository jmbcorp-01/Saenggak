import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:material_ui/material_ui.dart';

import '../api/backend.dart';
import '../core/typing_session.dart';
import '../l10n/l10n.dart';
import '../models/post.dart';
import '../models/profile.dart';
import '../models/publish_outcome.dart';
import '../models/social.dart';

/// The signed-in user's profile and the lists the screens show, kept in step
/// with the server after each change.
class AppState extends ChangeNotifier {
  AppState({required this.backend, DateTime Function()? clock, Future<String> Function()? deviceTimeZone})
    : clock = clock ?? DateTime.now,
      deviceTimeZone = deviceTimeZone ?? _deviceTimeZone;

  final Backend backend;
  final DateTime Function() clock;

  /// The device's IANA time zone, used for a new profile's writing day.
  final Future<String> Function() deviceTimeZone;

  static Future<String> _deviceTimeZone() async {
    try {
      return (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (_) {
      return 'Asia/Seoul';
    }
  }

  Profile? me;
  List<Post> feed = const [];
  List<Post> following = const [];
  List<Post> mine = const [];
  String? _feedNext;
  bool loading = false;

  /// The notifications tab: newest first, and how many arrived since last read.
  List<AppNotification> notifications = const [];
  int unreadNotifications = 0;
  String? error;

  /// Newer posts found by [checkForNew], held back until the reader asks for
  /// them so the timeline does not jump under their thumb.
  List<Post> incoming = const [];

  /// Posts that have just arrived at the top of the feed. They settle in with
  /// a little motion instead of popping in.
  Set<String> fresh = const {};

  /// Posts the reader saved, newest saved first. Loaded when the list opens.
  List<Post> saved = const [];

  /// The last search: people and posts close in meaning to [searchQuery].
  String searchQuery = '';
  List<PersonHit> people = const [];
  List<Post> found = const [];

  /// Posts opened on their own, such as from a shared link.
  List<Post> opened = const [];

  /// Shows the typing check and returns true once it is passed. The home
  /// screen sets it; without it a check request is an ordinary error.
  Future<bool> Function()? askHumanCheck;

  /// Runs [action]. When the server first wants a typing check, shows it and
  /// tries once more after it is passed.
  Future<T> guarded<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (e) {
      final ask = askHumanCheck;
      if (!isHumanCheck(e) || ask == null || !await ask()) rethrow;
      return action();
    }
  }

  /// Feed translations go into the reader's language.
  String get lang => AppLang.instance.value;
  bool get hasMore => _feedNext != null;

  /// Loads the profile and the first page of each list.
  Future<void> start() async {
    await loadMe();
    await loadLists();
  }

  /// The reader's own profile; null for a new account.
  Future<void> loadMe() async {
    me = await backend.me();
    // The language saved on the account follows the person to new devices.
    final saved = me?.locale;
    if (saved != null && saved != AppLang.instance.value) AppLang.instance.set(saved);
    notifyListeners();
  }

  /// The first page of each list. Until it arrives the feed shows
  /// placeholder rows.
  Future<void> loadLists() async {
    loading = true;
    notifyListeners();
    await Future.wait([refresh(), if (me != null) loadNotifications()]);
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
      final before = {for (final p in feed) p.id};
      feed = results[0].items;
      _feedNext = results[0].next;
      incoming = const [];
      incomingFollowing = const [];
      fresh = before.isEmpty ? const {} : {for (final p in feed.takeWhile((p) => !before.contains(p.id))) p.id};
      var k = 1;
      following = unlocked ? results[k++].items : const [];
      mine = me != null ? results[k].items : const [];
    } catch (_) {
      error = t('글을 불러오지 못했어요. 당겨서 다시 시도해주세요.');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Newer posts from people the reader follows, held for the 팔로잉 tab.
  List<Post> incomingFollowing = const [];

  /// Whether either tab has newer posts waiting, for the dot on home.
  bool get hasIncoming => incoming.isNotEmpty || incomingFollowing.isNotEmpty;

  /// Posts in [page] newer than everything in [shown] and [waiting], not the
  /// reader's own.
  static List<Post> _newer(List<Post> page, List<Post> shown, List<Post> waiting) {
    final known = {for (final p in shown) p.id, for (final p in waiting) p.id};
    // The 추천 tab is not in time order, so compare with its newest post.
    final newest = shown.map((p) => p.createdAt).reduce((a, b) => a.isAfter(b) ? a : b);
    return [
      for (final p in page)
        if (!known.contains(p.id) && !p.isMine && p.createdAt.isAfter(newest)) p,
    ];
  }

  /// Looks for posts newer than the top of each tab, without showing them.
  Future<void> checkForNew() async {
    if (loading) return;
    final unlocked = me?.followUnlocked ?? false;
    try {
      final pages = await Future.wait([
        if (feed.isNotEmpty) backend.feed(lang: lang),
        if (unlocked && following.isNotEmpty) backend.feed(lang: lang, following: true),
      ]);
      var k = 0;
      var changed = false;
      if (feed.isNotEmpty) {
        final found = _newer(pages[k++].items, feed, incoming);
        if (found.isNotEmpty) {
          incoming = [...found, ...incoming];
          changed = true;
        }
      }
      if (unlocked && following.isNotEmpty) {
        final found = _newer(pages[k].items, following, incomingFollowing);
        if (found.isNotEmpty) {
          incomingFollowing = [...found, ...incomingFollowing];
          changed = true;
        }
      }
      if (changed) notifyListeners();
    } catch (_) {
      // Quietly try again next time.
    }
  }

  /// Puts the posts [checkForNew] found at the top of the feed.
  void showIncoming() {
    if (incoming.isEmpty) return;
    fresh = {for (final p in incoming) p.id};
    feed = [...incoming, ...feed];
    incoming = const [];
    notifyListeners();
  }

  /// The same for the 팔로잉 tab.
  void showIncomingFollowing() {
    if (incomingFollowing.isEmpty) return;
    fresh = {for (final p in incomingFollowing) p.id};
    following = [...incomingFollowing, ...following];
    incomingFollowing = const [];
    notifyListeners();
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
      error = t('글을 더 불러오지 못했어요.');
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
    saved = apply(saved);
    found = apply(found);
    opened = apply(opened);
    notifyListeners();
  }

  /// Updates the count right away, then takes the server's numbers.
  Future<void> toggleEmpathy(Post post) async {
    if (post.isMine) return;
    final was = post.empathizedByMe;
    _replace(post.id, (p) => p.copyWith(empathizedByMe: !was, empathyCount: p.empathyCount + (was ? -1 : 1)));
    try {
      final r = await guarded(() => backend.toggleEmpathy(post.id));
      _replace(post.id, (p) => p.copyWith(empathizedByMe: r.empathized, empathyCount: r.count));
    } catch (_) {
      _replace(post.id, (p) => p.copyWith(empathizedByMe: was, empathyCount: post.empathyCount));
    }
  }

  Future<PublishOutcome> publish(String text, TypingSession session) async {
    final outcome = await _checked(
      () => backend.publish(text: text, session: session, localDate: localDateOf(clock())),
    );
    unawaited(_afterWrite(outcome));
    return outcome;
  }

  Future<PublishOutcome> edit(Post post, String text, TypingSession session) async {
    final outcome = await _checked(
      () => backend.edit(post.id, text: text, session: session, localDate: localDateOf(clock())),
    );
    unawaited(_afterWrite(outcome));
    return outcome;
  }

  /// A post refused for want of a typing check is sent again once it passes.
  Future<PublishOutcome> _checked(Future<PublishOutcome> Function() send) async {
    final outcome = await send();
    final ask = askHumanCheck;
    if (outcome is Rejected && outcome.reason == RejectReason.humanCheck && ask != null && await ask()) {
      return send();
    }
    return outcome;
  }

  /// Saves or unsaves at once, then confirms with the server.
  Future<void> toggleBookmark(Post post) async {
    final want = !post.bookmarked;
    _replace(post.id, (p) => p.copyWith(bookmarked: want));
    saved = want ? [post.copyWith(bookmarked: true), ...saved] : saved.where((p) => p.id != post.id).toList();
    notifyListeners();
    try {
      await backend.setBookmark(post.id, want);
    } catch (_) {
      _replace(post.id, (p) => p.copyWith(bookmarked: !want));
      await loadSaved();
      rethrow;
    }
  }

  Future<void> loadSaved() async {
    saved = await backend.bookmarks(lang: lang);
    notifyListeners();
  }

  /// Looks for people and for posts close in meaning. Short queries clear it.
  Future<void> search(String query) async {
    searchQuery = query.trim();
    if (searchQuery.isEmpty) {
      people = const [];
      found = const [];
      notifyListeners();
      return;
    }
    final asked = searchQuery;
    final results = await Future.wait([
      backend.searchPeople(asked),
      if (asked.replaceFirst('@', '').length >= 2 && !asked.startsWith('@'))
        backend.searchPosts(asked, lang: lang)
      else
        Future.value(const <Post>[]),
    ]);
    // A newer search may have started meanwhile.
    if (asked != searchQuery) return;
    people = results[0] as List<PersonHit>;
    found = results[1] as List<Post>;
    notifyListeners();
  }

  /// Fetches one post to show on its own page.
  Future<Post> open(String postId) async {
    final post = await backend.post(postId, lang: lang);
    opened = [post, ...opened.where((p) => p.id != postId)];
    notifyListeners();
    return post;
  }

  Future<void> report({String? postId, String? userId, required String reason}) =>
      guarded(() => backend.report(postId: postId, userId: userId, reason: reason));

  /// Brings the profile and lists up to date after a post. The writer sees
  /// the result at once: the profile takes the new counts from the answer,
  /// and the lists reload behind the result screen.
  Future<void> _afterWrite(PublishOutcome outcome) async {
    // A blocked post can take follow permission away, so refresh then too.
    if (outcome is Rejected && outcome.reason != RejectReason.blocked) return;
    final current = me;
    if (outcome is Published && current != null) {
      me = current.copyWith(writingDays: outcome.writingDays, followUnlocked: outcome.followUnlocked);
      notifyListeners();
    }
    try {
      me = await backend.me();
    } catch (_) {
      // The post went through; the lists catch up on the next refresh.
    }
    await refresh();
  }

  Future<void> delete(Post post) async {
    await backend.delete(post.id);
    found = found.where((p) => p.id != post.id).toList();
    opened = opened.where((p) => p.id != post.id).toList();
    saved = saved.where((p) => p.id != post.id).toList();
    feed = feed.where((p) => p.id != post.id).toList();
    following = following.where((p) => p.id != post.id).toList();
    mine = mine.where((p) => p.id != post.id).toList();
    me = await backend.me();
    notifyListeners();
  }

  /// A new profile takes the app's language and the device's time zone.
  Future<void> saveProfile({required String handle, required String displayName, String bio = ''}) async {
    final current = me;
    me = await backend.saveProfile(
      handle: handle,
      displayName: displayName,
      bio: bio,
      locale: current?.locale ?? AppLang.instance.value,
      timeZone: current?.timeZone ?? await deviceTimeZone(),
    );
    notifyListeners();
  }

  /// Changes the feed's language or the time zone that decides the writing day.
  Future<void> saveSettings({String? locale, String? timeZone}) async {
    final current = me!;
    me = await backend.saveProfile(
      handle: current.handle,
      displayName: current.displayName,
      bio: current.bio,
      locale: locale ?? current.locale,
      timeZone: timeZone ?? current.timeZone,
    );
    notifyListeners();
    if (locale != null && locale != current.locale) await refresh();
  }

  /// Switches the app's language at once, then saves it on the account so
  /// the feed is translated into it.
  Future<void> setLanguage(String lang) async {
    AppLang.instance.set(lang);
    notifyListeners();
    if (me != null && me!.locale != lang) await saveSettings(locale: lang);
  }

  /// Erases the account on the server and signs out.
  Future<void> deleteAccount() async {
    await backend.deleteAccount();
    await signOut();
  }

  /// Throws [ApiException] with the reason when the server turns the photo down.
  Future<void> setPhoto(Uint8List jpeg) async {
    me = await backend.setPhoto(jpeg);
    notifyListeners();
  }

  Future<void> loadNotifications() async {
    try {
      final page = await backend.notifications();
      notifications = page.items;
      unreadNotifications = page.unread;
      notifyListeners();
    } catch (_) {
      // The tab keeps what it had; the next open tries again.
    }
  }

  /// Called when the notifications tab is opened.
  Future<void> markNotificationsSeen() async {
    if (unreadNotifications == 0) return;
    unreadNotifications = 0;
    notifyListeners();
    try {
      await backend.markNotificationsSeen();
    } catch (_) {}
  }

  /// Hides the person's posts at once; the server also ends follows both ways.
  Future<void> block(String userId) async {
    await guarded(() => backend.block(userId));
    feed = feed.where((p) => p.authorId != userId).toList();
    following = following.where((p) => p.authorId != userId).toList();
    notifications = notifications.where((n) => n.actorId != userId).toList();
    notifyListeners();
  }

  Future<void> unblock(String userId) async {
    await backend.unblock(userId);
    await refresh();
  }

  /// Admins only: takes someone's post out of every list.
  Future<void> adminRemove(Post post, String note) async {
    await backend.removePost(post.id, note: note);
    feed = feed.where((p) => p.id != post.id).toList();
    following = following.where((p) => p.id != post.id).toList();
    notifyListeners();
  }

  /// Signs out and forgets everything shown, so the next person starts clean.
  Future<void> signOut() async {
    await backend.signOut();
    me = null;
    feed = following = mine = saved = found = opened = incoming = incomingFollowing = const [];
    people = const [];
    searchQuery = '';
    notifications = const [];
    unreadNotifications = 0;
    _feedNext = null;
    error = null;
    notifyListeners();
  }

  /// Turns alerts for [user]'s new posts on or off and returns the profile.
  Future<Profile> setPostAlerts(Profile user, bool on) async {
    await backend.setPostAlerts(user.id, on);
    return user.copyWith(alertsOn: on);
  }

  /// Follows or unfollows and returns the updated profile.
  Future<Profile> setFollowing(Profile user, bool follow) async {
    if (follow) {
      await guarded(() => backend.follow(user.id));
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
