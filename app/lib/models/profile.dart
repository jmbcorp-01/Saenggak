/// A writer's profile and follow status.
class Profile {
  const Profile({
    required this.id,
    required this.handle,
    required this.displayName,
    this.bio = '',
    this.locale = 'ko',
    this.timeZone = 'Asia/Seoul',
    this.writingDays = 0,
    this.daysToFollow = 10,
    this.followUnlocked = false,
    this.followers = 0,
    this.following = 0,
    this.followedByMe = false,
    this.isMe = false,
  });

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
    id: j['id'] as String,
    handle: j['handle'] as String,
    displayName: j['displayName'] as String,
    bio: j['bio'] as String? ?? '',
    locale: j['locale'] as String? ?? 'ko',
    timeZone: j['timeZone'] as String? ?? 'Asia/Seoul',
    writingDays: (j['writingDays'] as num? ?? 0).toInt(),
    daysToFollow: (j['daysToFollow'] as num? ?? 10).toInt(),
    followUnlocked: j['followUnlocked'] as bool? ?? false,
    followers: (j['followers'] as num? ?? 0).toInt(),
    following: (j['following'] as num? ?? 0).toInt(),
    followedByMe: j['followedByMe'] as bool? ?? false,
    isMe: j['isMe'] as bool? ?? false,
  );

  final String id;
  final String handle;
  final String displayName;
  final String bio;
  final String locale;
  final String timeZone;
  final int writingDays;
  final int daysToFollow;
  final bool followUnlocked;
  final int followers;
  final int following;
  final bool followedByMe;
  final bool isMe;

  String get initial => displayName.isEmpty ? '?' : String.fromCharCode(displayName.runes.first).toUpperCase();

  Profile copyWith({bool? followedByMe, int? followers, int? writingDays, bool? followUnlocked}) => Profile(
    id: id,
    handle: handle,
    displayName: displayName,
    bio: bio,
    locale: locale,
    timeZone: timeZone,
    writingDays: writingDays ?? this.writingDays,
    daysToFollow: daysToFollow,
    followUnlocked: followUnlocked ?? this.followUnlocked,
    followers: followers ?? this.followers,
    following: following,
    followedByMe: followedByMe ?? this.followedByMe,
    isMe: isMe,
  );
}
