import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoSliverRefreshControl, RefreshIndicatorMode;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../data/app_state.dart';
import '../models/post.dart';
import '../theme/tokens.dart';
import '../widgets/appear.dart';
import '../widgets/post_actions.dart';
import '../widgets/post_tile.dart';
import '../widgets/refresh_mark.dart';
import '../widgets/shell_chrome.dart';
import '../widgets/skeleton.dart';
import '../widgets/symbol_mark.dart';

/// Timeline with "추천" (everyone) and "팔로잉" tabs.
///
/// The header floats over the list with a frosted background. On a phone it
/// slides away while scrolling down, along with the bottom menu.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key, required this.state, required this.onOpenProfile, this.homeAgain});

  final AppState state;
  final VoidCallback onOpenProfile;

  /// Bumped when home is tapped while open: scroll to the top, or refresh if
  /// already there.
  final ValueListenable<int>? homeAgain;

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this);
  final _scrolls = [ScrollController(), ScrollController()];

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) HapticFeedback.selectionClick();
    });
    widget.homeAgain?.addListener(_onHomeAgain);
  }

  @override
  void didUpdateWidget(FeedScreen old) {
    super.didUpdateWidget(old);
    if (old.homeAgain != widget.homeAgain) {
      old.homeAgain?.removeListener(_onHomeAgain);
      widget.homeAgain?.addListener(_onHomeAgain);
    }
  }

  @override
  void dispose() {
    widget.homeAgain?.removeListener(_onHomeAgain);
    _tabs.dispose();
    for (final c in _scrolls) {
      c.dispose();
    }
    super.dispose();
  }

  void _onHomeAgain() {
    final c = _scrolls[_tabs.index];
    if (!c.hasClients) return;
    if (c.offset > 1) {
      _toTop(c);
    } else {
      state.refresh();
    }
  }

  void _toTop(ScrollController c) {
    if (!c.hasClients) return;
    // Long jumps are shortened so the motion stays quick.
    if (c.offset > 3000) c.jumpTo(3000);
    c.animateTo(0, duration: SgMotion.slow + SgMotion.medium, curve: SgMotion.emphasized);
  }

  void _showIncoming() {
    HapticFeedback.lightImpact();
    state.showIncoming();
    _tabs.animateTo(0);
    _toTop(_scrolls[0]);
  }

  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.sizeOf(context).width < SgBreakpoints.rail;
    final headerHeight = (phone ? _FeedHeader.barHeight : 0) + _FeedHeader.tabsHeight;
    final visible = !phone || ShellChrome.visibleOf(context);
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => Stack(
        children: [
          TabBarView(
            controller: _tabs,
            children: [
              _PostList(
                state: state,
                controller: _scrolls[0],
                top: headerHeight,
                posts: state.feed,
                loadMore: state.hasMore ? state.loadMore : null,
              ),
              if (state.me?.followUnlocked ?? false)
                _PostList(
                  state: state,
                  controller: _scrolls[1],
                  top: headerHeight,
                  posts: state.following,
                  empty: '아직 팔로우한 사람이 없어요. 글쓴이 이름을 눌러 프로필에서 팔로우할 수 있어요.',
                )
              else
                _FollowingLocked(
                  top: headerHeight,
                  days: state.me?.writingDays ?? 0,
                  total: state.me?.daysToFollow ?? 10,
                ),
            ],
          ),
          AnimatedPositioned(
            duration: SgMotion.slow,
            curve: SgMotion.ease,
            top: visible ? 0 : -headerHeight,
            left: 0,
            right: 0,
            child: _FeedHeader(state: state, tabs: _tabs, showBar: phone, onOpenProfile: widget.onOpenProfile),
          ),
          // "새 생각 3개": newer posts are waiting above.
          AnimatedPositioned(
            duration: SgMotion.slow,
            curve: SgMotion.ease,
            top: (visible ? headerHeight : 0) + SgSpace.md,
            left: 0,
            right: 0,
            child: Center(
              child: _NewPostsPill(posts: state.incoming, onTap: _showIncoming),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedHeader extends StatelessWidget {
  const _FeedHeader({required this.state, required this.tabs, required this.showBar, required this.onOpenProfile});

  static const barHeight = 52.0;
  static const tabsHeight = 48.0;

  final AppState state;
  final TabController tabs;

  /// The row with the profile photo and symbol, on phones only. Wider
  /// screens have them in the side menu.
  final bool showBar;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: ColoredBox(
          color: SgColors.scrim,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showBar)
                SizedBox(
                  height: barHeight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: SgSpace.sm),
                    child: Row(
                      children: [
                        Semantics(
                          button: true,
                          label: '내 프로필',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onOpenProfile,
                            // A 32px photo in a 48px touch area.
                            child: SizedBox.square(
                              dimension: 48,
                              child: Center(
                                child: ExcludeSemantics(
                                  child: Avatar(
                                    initial: state.me?.initial ?? '?',
                                    color: avatarPalette[(state.me?.id.hashCode ?? 0).abs() % avatarPalette.length],
                                    size: 32,
                                    photoUrl: state.me?.photoUrl,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const Expanded(child: Center(child: SymbolMark())),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
                ),
              SizedBox(
                height: tabsHeight,
                child: TabBar(
                  controller: tabs,
                  labelColor: SgColors.ink,
                  unselectedLabelColor: SgColors.muted,
                  labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  unselectedLabelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  indicatorSize: TabBarIndicatorSize.label,
                  indicator: UnderlineTabIndicator(
                    borderSide: BorderSide(color: SgColors.accent, width: 3),
                    borderRadius: const BorderRadius.all(Radius.circular(2)),
                  ),
                  overlayColor: WidgetStateProperty.resolveWith(
                    (s) => s.contains(WidgetState.pressed)
                        ? SgColors.pressed
                        : s.contains(WidgetState.hovered)
                        ? SgColors.hover
                        : null,
                  ),
                  dividerColor: SgColors.line,
                  tabs: const [
                    Tab(text: '추천'),
                    Tab(text: '팔로잉'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewPostsPill extends StatelessWidget {
  const _NewPostsPill({required this.posts, required this.onTap});

  final List<Post> posts;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final show = posts.isNotEmpty;
    final faces = {for (final p in posts) p.authorId: p}.values.take(3).toList();
    return IgnorePointer(
      ignoring: !show,
      child: AnimatedSlide(
        offset: show ? Offset.zero : const Offset(0, -0.6),
        duration: SgMotion.slow,
        curve: show ? SgMotion.spring : SgMotion.ease,
        child: AnimatedOpacity(
          opacity: show ? 1 : 0,
          duration: SgMotion.medium,
          child: Material(
            color: SgColors.accent,
            shape: const StadiumBorder(),
            elevation: 4,
            shadowColor: Colors.black.withValues(alpha: 0.3),
            child: InkWell(
              key: const Key('new-posts'),
              customBorder: const StadiumBorder(),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(SgSpace.md, SgSpace.xs + 2, SgSpace.lg, SgSpace.xs + 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(SgIcons.up, size: 18, color: SgColors.onAccent),
                    const SizedBox(width: SgSpace.xs),
                    SizedBox(
                      width: faces.isEmpty ? 0 : 24.0 + 14 * (faces.length - 1),
                      height: 24,
                      child: Stack(
                        children: [
                          for (var i = 0; i < faces.length; i++)
                            Positioned(
                              left: 14.0 * i,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: SgColors.accent, width: 1.5),
                                ),
                                child: Avatar(
                                  initial: faces[i].authorInitial,
                                  color: faces[i].avatarColor,
                                  photoUrl: faces[i].authorPhotoUrl,
                                  size: 21,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: SgSpace.sm),
                    Text('새 생각 ${posts.length}개', style: SgText.label(size: 14).copyWith(color: SgColors.onAccent)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PostList extends StatefulWidget {
  const _PostList({
    required this.state,
    required this.controller,
    required this.top,
    required this.posts,
    this.loadMore,
    this.empty = '아직 올라온 글이 없어요.',
  });

  final AppState state;
  final ScrollController controller;

  /// Room left at the top for the floating header.
  final double top;
  final List<Post> posts;
  final VoidCallback? loadMore;
  final String empty;

  @override
  State<_PostList> createState() => _PostListState();
}

class _PostListState extends State<_PostList> {
  /// Posts shown in the first moment settle in one after another; after that
  /// only newly arrived ones do.
  late final _mounted = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final posts = widget.posts;
    final opening = DateTime.now().difference(_mounted) < const Duration(milliseconds: 800);
    final bottom = MediaQuery.paddingOf(context).bottom + 96;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (widget.loadMore != null && n.metrics.extentAfter < 400) widget.loadMore!();
        return false;
      },
      child: Scrollbar(
        controller: widget.controller,
        child: CustomScrollView(
          controller: widget.controller,
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          slivers: [
            CupertinoSliverRefreshControl(
              refreshTriggerPullDistance: 90,
              refreshIndicatorExtent: 64,
              onRefresh: () {
                HapticFeedback.mediumImpact();
                return state.refresh();
              },
              builder: (context, mode, pulled, trigger, extent) =>
                  _RefreshBuilder(top: widget.top, mode: mode, pulled: pulled, trigger: trigger),
            ),
            SliverToBoxAdapter(child: SizedBox(height: widget.top)),
            if (state.error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(SgSpace.lg),
                  child: Text(state.error!, style: SgText.small.copyWith(color: SgColors.accentText)),
                ),
              ),
            if (posts.isEmpty && state.loading) const SliverToBoxAdapter(child: PostSkeletonList()),
            if (posts.isEmpty && !state.loading)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(SgSpace.xxl),
                  child: Text(widget.empty, textAlign: TextAlign.center, style: SgText.small),
                ),
              ),
            SliverList.builder(
              itemCount: posts.length,
              itemBuilder: (context, i) {
                final p = posts[i];
                final fresh = state.fresh.contains(p.id);
                return Appear(
                  key: ValueKey(p.id),
                  enabled: fresh || (opening && i < 8),
                  delay: Duration(milliseconds: 40 * math.min(i, 8)),
                  child: ConnectedPostTile(state: state, post: p),
                );
              },
            ),
            if (state.loading && posts.isNotEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(SgSpace.xl),
                  child: Center(
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                ),
              ),
            SliverToBoxAdapter(child: SizedBox(height: bottom)),
          ],
        ),
      ),
    );
  }
}

/// The pull-to-refresh mark. The refresh area sits under the floating header,
/// so the mark is drawn just below the header instead.
class _RefreshBuilder extends StatelessWidget {
  const _RefreshBuilder({required this.top, required this.mode, required this.pulled, required this.trigger});

  final double top;
  final RefreshIndicatorMode mode;
  final double pulled;
  final double trigger;

  @override
  Widget build(BuildContext context) {
    if (mode == RefreshIndicatorMode.inactive) return const SizedBox.shrink();
    return OverflowBox(
      alignment: Alignment.topCenter,
      maxHeight: double.infinity,
      child: Padding(
        padding: EdgeInsets.only(top: top),
        child: SizedBox(
          height: pulled,
          child: Center(
            child: RefreshMark(
              progress: (pulled / trigger).clamp(0.0, 1.0),
              spinning: mode == RefreshIndicatorMode.refresh || mode == RefreshIndicatorMode.armed,
            ),
          ),
        ),
      ),
    );
  }
}

class _FollowingLocked extends StatelessWidget {
  const _FollowingLocked({required this.top, required this.days, required this.total});

  final double top;
  final int days;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(SgSpace.xxl, top + SgSpace.xxl, SgSpace.xxl, SgSpace.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SymbolMark(size: 48, semanticLabel: null),
          const SizedBox(height: SgSpace.lg),
          Text('${total - days}일 더 쓰면 팔로우할 수 있어요', style: SgText.title.copyWith(fontSize: 17)),
          const SizedBox(height: SgSpace.sm),
          Text('글을 쓴 날이 $total일이 되면 팔로우가 열려요. 연속이 아니어도 돼요.', textAlign: TextAlign.center, style: SgText.small),
        ],
      ),
    );
  }
}
