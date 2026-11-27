import '../l10n/l10n.dart';

/// A published thought, as the reader sees it.
class Post {
  const Post({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.authorHandle,
    required this.body,
    required this.lang,
    required this.createdAt,
    required this.typingTime,
    required this.empathyCount,
    this.translation,
    this.editedAt,
    this.empathizedByMe = false,
    this.bookmarked = false,
    this.isMine = false,
    this.authorPhotoUrl,
  });

  factory Post.fromJson(Map<String, dynamic> j, {required String myId}) {
    final translation = j['translation'] as Map<String, dynamic>?;
    return Post(
      id: j['id'] as String,
      authorId: j['authorId'] as String,
      authorName: j['authorName'] as String,
      authorHandle: j['authorHandle'] as String,
      body: j['body'] as String,
      lang: j['lang'] as String,
      translation: translation?['body'] as String?,
      createdAt: parseServerTime(j['createdAt'] as String),
      editedAt: j['editedAt'] == null ? null : parseServerTime(j['editedAt'] as String),
      typingTime: Duration(milliseconds: (j['typingMs'] as num).toInt()),
      empathyCount: (j['empathyCount'] as num).toInt(),
      empathizedByMe: j['empathizedByMe'] as bool? ?? false,
      bookmarked: j['bookmarkedByMe'] as bool? ?? false,
      isMine: j['authorId'] == myId,
      authorPhotoUrl: j['photoUrl'] as String?,
    );
  }

  final String id;
  final String authorId;
  final String authorName;
  final String authorHandle;

  /// The text as the author typed it.
  final String body;
  final String lang;

  /// The body in the reader's language, when it was written in another one.
  final String? translation;

  final DateTime createdAt;
  final DateTime? editedAt;
  final Duration typingTime;
  final int empathyCount;
  final bool empathizedByMe;

  /// Saved by the reader to read again.
  final bool bookmarked;
  final bool isMine;

  /// The author's profile photo, or null when they have none.
  final String? authorPhotoUrl;

  /// Posts can be edited only until they get their first empathy.
  bool get editable => isMine && empathyCount == 0;

  /// The server's cursor for the next page is this post's creation time.
  String get cursor => createdAt.toUtc().toIso8601String();

  String get authorInitial => authorName.isEmpty ? '?' : authorName.characters.first.toUpperCase();

  /// Behind the initial when the author has no photo.
  int get avatarColor => avatarPalette[authorId.hashCode.abs() % avatarPalette.length];

  Post copyWith({int? empathyCount, bool? empathizedByMe, bool? bookmarked}) => Post(
    id: id,
    authorId: authorId,
    authorName: authorName,
    authorHandle: authorHandle,
    body: body,
    lang: lang,
    translation: translation,
    createdAt: createdAt,
    editedAt: editedAt,
    typingTime: typingTime,
    empathyCount: empathyCount ?? this.empathyCount,
    empathizedByMe: empathizedByMe ?? this.empathizedByMe,
    bookmarked: bookmarked ?? this.bookmarked,
    isMine: isMine,
    authorPhotoUrl: authorPhotoUrl,
  );

  /// The same post with its author's current name, handle and photo, after
  /// the author changed their profile.
  Post withAuthor({required String name, required String handle, required String? photoUrl}) => Post(
    id: id,
    authorId: authorId,
    authorName: name,
    authorHandle: handle,
    body: body,
    lang: lang,
    translation: translation,
    createdAt: createdAt,
    editedAt: editedAt,
    typingTime: typingTime,
    empathyCount: empathyCount,
    empathizedByMe: empathizedByMe,
    bookmarked: bookmarked,
    isMine: isMine,
    authorPhotoUrl: photoUrl,
  );
}

const avatarPalette = [0xFF3B4A42, 0xFFC7B9A5, 0xFFE4DDD2, 0xFF6E5B4B, 0xFF8A9A8E, 0xFFB9A38C];

/// Postgres text timestamps ("2026-11-25 01:02:03.45+00") and ISO strings.
DateTime parseServerTime(String s) {
  var t = s.trim().replaceFirst(' ', 'T');
  // "+00" → "+00:00" so Dart accepts the offset.
  t = t.replaceFirstMapped(RegExp(r'([+-]\d{2})$'), (m) => '${m[1]}:00');
  return DateTime.parse(t);
}

/// "방금", "5분", "3시간", "2일", or a date for older posts.
String timeAgo(DateTime at, DateTime now) {
  final d = now.difference(at);
  if (d.inMinutes < 1) return t('방금');
  if (d.inHours < 1) return t('{0}분', [d.inMinutes]);
  if (d.inDays < 1) return t('{0}시간', [d.inHours]);
  if (d.inDays < 7) return t('{0}일', [d.inDays]);
  final local = at.toLocal();
  if (AppLang.instance.value == 'en') return '${_months[local.month - 1]} ${local.day}';
  return t('{0}월 {1}일', [local.month, local.day]);
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String languageName(String code) => switch (code) {
  'en' => t('영어'),
  'ko' => t('한국어'),
  _ => code,
};

extension on String {
  Iterable<String> get characters => runes.map(String.fromCharCode);
}
