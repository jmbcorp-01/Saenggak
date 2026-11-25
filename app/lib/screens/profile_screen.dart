import 'package:material_ui/material_ui.dart';

import '../api/backend.dart';
import '../data/app_state.dart';
import '../models/post.dart';
import '../models/profile.dart';
import '../theme/tokens.dart';
import '../widgets/post_actions.dart';
import '../widgets/post_tile.dart';
import '../widgets/symbol_mark.dart';
import 'profile_setup_screen.dart';

/// A writer's profile: photo, counts, follow progress or button, and posts.
/// Without [userId] (or with the reader's own id) it is the reader's own.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.state, this.userId});

  final AppState state;
  final String? userId;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Profile? _other;
  List<Post> _otherPosts = const [];
  String? _error;
  bool _busy = false;

  bool get _isMe => widget.userId == null || widget.userId == widget.state.me?.id;

  @override
  void initState() {
    super.initState();
    if (!_isMe) _load();
  }

  Future<void> _load() async {
    final state = widget.state;
    try {
      final results = await Future.wait([
        state.backend.user(widget.userId!),
        state.backend.feed(lang: state.lang, authorId: widget.userId),
      ]);
      if (!mounted) return;
      setState(() {
        _other = results[0] as Profile;
        _otherPosts = (results[1] as FeedPage).items;
      });
    } catch (_) {
      if (mounted) setState(() => _error = '프로필을 불러오지 못했어요.');
    }
  }

  Future<void> _toggleFollow(Profile user) async {
    setState(() => _busy = true);
    try {
      final updated = await widget.state.setFollowing(user, !user.followedByMe);
      if (mounted) setState(() => _other = updated);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.code == 'not_allowed' ? '팔로우는 두 사람 모두 글을 쓴 날이 10일이 되면 열려요.' : '팔로우하지 못했어요. 다시 시도해주세요.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final profile = _isMe ? widget.state.me : _other;
        if (profile == null) {
          return Center(child: Text(_error ?? '', style: SgText.small));
        }
        final posts = _isMe ? widget.state.mine : _otherPosts;
        // Others' posts are kept in step with 공감 made from the feed.
        final shown = _isMe
            ? posts
            : [
                for (final p in posts)
                  [...widget.state.feed, ...widget.state.following].where((f) => f.id == p.id).firstOrNull ?? p,
              ];
        final received = shown.fold<int>(0, (s, p) => s + p.empathyCount);
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            // Band, photo overlapping its lower edge, and the action button.
            SizedBox(
              height: 104 + 60,
              child: Stack(
                children: [
                  Container(
                    height: 104,
                    decoration: const BoxDecoration(color: SgColors.band),
                    alignment: Alignment.topRight,
                    clipBehavior: Clip.hardEdge,
                    child: const SymbolMark(
                      size: 150,
                      strokeColor: SgColors.bandMark,
                      dotColor: SgColors.bandMark,
                      semanticLabel: null,
                    ),
                  ),
                  Positioned(
                    left: 16,
                    top: 104 - 44,
                    child: Container(
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                      padding: const EdgeInsets.all(4),
                      child: Avatar(
                        initial: profile.initial,
                        color: avatarPalette[profile.id.hashCode.abs() % avatarPalette.length],
                        size: 80,
                        label: '${profile.displayName} 프로필 사진',
                      ),
                    ),
                  ),
                  Positioned(
                    right: 16,
                    top: 104 + 6,
                    child: _isMe
                        ? OutlinedButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (context) =>
                                    ProfileSetupScreen(state: widget.state, onDone: () => Navigator.of(context).pop()),
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: SgColors.ink,
                              side: const BorderSide(color: SgColors.outline),
                              minimumSize: const Size(0, 40),
                              textStyle: SgText.label(size: 14),
                            ),
                            child: const Text('프로필 수정'),
                          )
                        : _FollowButton(
                            profile: profile,
                            canFollow: (widget.state.me?.followUnlocked ?? false) && profile.followUnlocked,
                            busy: _busy,
                            onPressed: () => _toggleFollow(profile),
                          ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(profile.displayName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  Text('@${profile.handle}', style: SgText.meta),
                  if (profile.bio.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(profile.bio, style: const TextStyle(fontSize: 15, height: 1.5)),
                  ],
                  const SizedBox(height: 10),
                  // Follow counts mean nothing until follow is open, so they are left out.
                  Text.rich(
                    TextSpan(
                      style: SgText.small,
                      children: [
                        if (profile.followUnlocked) ...[
                          _count('${profile.following}'),
                          const TextSpan(text: ' 팔로잉    '),
                          _count('${profile.followers}'),
                          const TextSpan(text: ' 팔로워    '),
                        ],
                        _count('$received'),
                        const TextSpan(text: ' 받은 공감'),
                      ],
                    ),
                  ),
                  if (_isMe && !profile.followUnlocked) ...[
                    const SizedBox(height: 14),
                    FollowProgress(days: profile.writingDays, total: profile.daysToFollow),
                  ],
                  if (!_isMe &&
                      !profile.followedByMe &&
                      !((widget.state.me?.followUnlocked ?? false) && profile.followUnlocked)) ...[
                    const SizedBox(height: 10),
                    Text(
                      (widget.state.me?.followUnlocked ?? false)
                          ? '${profile.displayName}님이 글을 쓴 날이 ${profile.daysToFollow}일이 되면 팔로우할 수 있어요.'
                          : '내가 글을 쓴 날이 ${widget.state.me?.daysToFollow ?? 10}일이 되면 팔로우할 수 있어요. '
                                '지금 ${widget.state.me?.writingDays ?? 0}일째예요.',
                      style: SgText.small,
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            if (shown.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text('아직 쓴 글이 없어요.', textAlign: TextAlign.center, style: SgText.small),
              ),
            for (final p in shown)
              ConnectedPostTile(key: ValueKey(p.id), state: widget.state, post: p, openAuthor: false),
          ],
        );
      },
    );
  }

  TextSpan _count(String n) => TextSpan(
    text: n,
    style: const TextStyle(color: SgColors.ink, fontWeight: FontWeight.w700),
  );
}

class _FollowButton extends StatelessWidget {
  const _FollowButton({required this.profile, required this.canFollow, required this.busy, required this.onPressed});

  final Profile profile;
  final bool canFollow;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final following = profile.followedByMe;
    final style = following
        ? OutlinedButton.styleFrom(
            foregroundColor: SgColors.ink,
            side: const BorderSide(color: SgColors.outline),
            textStyle: SgText.label(size: 14, weight: FontWeight.w700),
          )
        : OutlinedButton.styleFrom(
            backgroundColor: SgColors.ink,
            foregroundColor: Colors.white,
            disabledBackgroundColor: SgColors.line,
            disabledForegroundColor: SgColors.muted,
            side: BorderSide.none,
            textStyle: SgText.label(size: 14, weight: FontWeight.w700),
          );
    final button = OutlinedButton(
      key: const Key('follow'),
      onPressed: busy || (!following && !canFollow) ? null : onPressed,
      style: style,
      child: Text(following ? '팔로잉' : '팔로우'),
    );
    return button;
  }
}

/// "팔로우까지 3일" with one segment per writing day.
class FollowProgress extends StatelessWidget {
  const FollowProgress({super.key, required this.days, this.total = 10});

  final int days;
  final int total;

  @override
  Widget build(BuildContext context) {
    final done = days.clamp(0, total);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        border: Border.all(color: SgColors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('팔로우까지 ${total - done}일', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              Text('$done / $total', style: SgText.mono.copyWith(fontSize: 13)),
            ],
          ),
          const SizedBox(height: 10),
          Semantics(
            label: '$total일 중 $done일 작성',
            child: Row(
              children: [
                for (var i = 0; i < total; i++)
                  Expanded(
                    child: Container(
                      height: 6,
                      margin: EdgeInsets.only(right: i == total - 1 ? 0 : 4),
                      decoration: BoxDecoration(
                        color: i < done ? SgColors.accent : SgColors.line,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text('글을 쓴 날이 $total일이 되면 팔로우가 열려요. 연속이 아니어도 돼요.', style: SgText.small),
        ],
      ),
    );
  }
}
