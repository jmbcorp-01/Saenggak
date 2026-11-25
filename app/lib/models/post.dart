/// A published thought.
class Post {
  const Post({
    required this.id,
    required this.authorName,
    required this.authorHandle,
    required this.authorInitial,
    required this.avatarColor,
    required this.body,
    required this.postedAgo,
    required this.typingTime,
    required this.empathyCount,
    this.empathizedByMe = false,
    this.translatedFrom,
    this.isMine = false,
  });

  final String id;
  final String authorName;
  final String authorHandle;

  /// Shown in place of the profile photo until photos are wired up.
  final String authorInitial;
  final int avatarColor;

  final String body;
  final String postedAgo;
  final Duration typingTime;
  final int empathyCount;
  final bool empathizedByMe;

  /// Original language name when the body shown is a translation.
  final String? translatedFrom;

  final bool isMine;

  /// Posts can be edited only until they get their first empathy.
  bool get editable => isMine && empathyCount == 0;

  Post copyWith({int? empathyCount, bool? empathizedByMe}) => Post(
        id: id,
        authorName: authorName,
        authorHandle: authorHandle,
        authorInitial: authorInitial,
        avatarColor: avatarColor,
        body: body,
        postedAgo: postedAgo,
        typingTime: typingTime,
        empathyCount: empathyCount ?? this.empathyCount,
        empathizedByMe: empathizedByMe ?? this.empathizedByMe,
        translatedFrom: translatedFrom,
        isMine: isMine,
      );
}
