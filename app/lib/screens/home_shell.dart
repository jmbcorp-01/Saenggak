import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/nav.dart';
import '../data/app_state.dart';
import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import '../widgets/right_panel.dart';
import '../widgets/shell_chrome.dart';
import '../widgets/side_nav.dart';
import '../core/links.dart';
import 'compose_screen.dart';
import 'feed_screen.dart';
import 'human_check_screen.dart';
import 'notifications_screen.dart';
import 'post_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

/// The signed-in app: home, search, notifications and profile, and the write
/// button.
///
/// On a phone the menu is at the bottom. From [SgBreakpoints.rail] it moves to
/// the left and the timeline becomes a centered column; from
/// [SgBreakpoints.full] a panel appears on the right. Each tab keeps its own
/// page history, so opening a profile keeps the menus in place.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.state, this.checkEvery = const Duration(minutes: 1), this.openPostId});

  final AppState state;

  /// A post to open over the timeline, as from a shared link. On the web it
  /// comes from the address.
  final String? openPostId;

  /// How often to look for new posts while the app is open.
  final Duration checkEvery;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;
  static const _home = 0, _alerts = 2, _profile = 3;
  final _navigators = List.generate(4, (_) => GlobalKey<NavigatorState>());
  final _chrome = ValueNotifier(true);

  /// Counts taps on the home button while home is open: the feed scrolls to
  /// the top, or refreshes if it is already there.
  final _homeAgain = ValueNotifier(0);
  Timer? _check;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check = Timer.periodic(widget.checkEvery, (_) => state.checkForNew());
    state.askHumanCheck = _askHumanCheck;
    final linked = widget.openPostId ?? linkedPostId();
    if (linked != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _navigators[_home].currentState?.push(
          MaterialPageRoute<void>(
            builder: (_) => PostScreen(state: state, postId: linked),
          ),
        ),
      );
    }
  }

  /// Only one typing check at a time, however many actions asked for it.
  Future<bool>? _checking;

  Future<bool> _askHumanCheck() {
    if (!mounted) return Future.value(false);
    return _checking ??= pushModal<bool>(
      context,
      (_) => HumanCheckScreen(backend: state.backend, lang: state.lang),
    ).then((passed) => passed ?? false).whenComplete(() => _checking = null);
  }

  @override
  void dispose() {
    _check?.cancel();
    if (state.askHumanCheck == _askHumanCheck) state.askHumanCheck = null;
    WidgetsBinding.instance.removeObserver(this);
    _chrome.dispose();
    _homeAgain.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) state.checkForNew();
  }

  void _select(int i) {
    HapticFeedback.selectionClick();
    _chrome.value = true;
    if (i == _tab) {
      // A second tap goes back to the start of the tab.
      final nav = _navigators[i].currentState;
      if (nav != null && nav.canPop()) {
        nav.popUntil((r) => r.isFirst);
      } else if (i == _home) {
        _homeAgain.value++;
      }
      return;
    }
    setState(() => _tab = i);
    if (i == _alerts) {
      state.loadNotifications().then((_) => state.markNotificationsSeen());
    }
  }

  void _compose() => pushModal<void>(context, (_) => ComposeScreen(state: state));

  void _openAuthor(String userId) {
    final nav = _navigators[_tab].currentState;
    if (userId == state.me?.id) {
      _select(_profile);
      return;
    }
    nav?.push(
      MaterialPageRoute<void>(
        builder: (_) => ProfilePage(state: state, userId: userId),
      ),
    );
  }

  List<NavItem> _items() => [
    NavItem(icon: SgIcons.home, activeIcon: SgIcons.homeActive, label: t('홈')),
    NavItem(icon: SgIcons.search, activeIcon: SgIcons.searchActive, label: t('검색')),
    NavItem(icon: SgIcons.bell, activeIcon: SgIcons.bellActive, label: t('알림'), badge: state.unreadNotifications),
    NavItem(icon: SgIcons.person, activeIcon: SgIcons.personActive, label: t('프로필')),
  ];

  Widget _tabs() {
    final roots = <WidgetBuilder>[
      (_) => FeedScreen(state: state, onOpenProfile: () => _select(_profile), homeAgain: _homeAgain),
      (_) => SearchScreen(state: state),
      (_) => NotificationsScreen(state: state),
      (_) => ProfileScreen(state: state),
    ];
    return NavigatorPopHandler<Object?>(
      onPopWithResult: (_) => _navigators[_tab].currentState?.maybePop(),
      child: IndexedStack(
        index: _tab,
        children: [
          for (var i = 0; i < roots.length; i++)
            // Only the open tab's pages take part in focus and hero animations.
            TickerMode(
              enabled: i == _tab,
              child: Navigator(
                key: _navigators[i],
                onGenerateRoute: (settings) => MaterialPageRoute<void>(settings: settings, builder: roots[i]),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final body = NotificationListener<ScrollNotification>(
      onNotification: (n) => ShellChrome.track(_chrome, n),
      child: _tabs(),
    );
    return ShellChrome(
      visible: _chrome,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => width < SgBreakpoints.rail ? _phone(context, body) : _wide(context, body, width),
      ),
    );
  }

  Widget _phone(BuildContext context, Widget body) {
    final items = _items();
    return Scaffold(
      // Pages scroll under the bottom menu, which slides away on the way down.
      extendBody: true,
      body: SafeArea(bottom: false, child: body),
      floatingActionButton: ValueListenableBuilder(
        valueListenable: _chrome,
        builder: (context, visible, child) => AnimatedOpacity(
          opacity: visible ? 1 : 0.5,
          duration: SgMotion.medium,
          child: AnimatedScale(scale: visible ? 1 : 0.9, duration: SgMotion.medium, curve: SgMotion.ease, child: child),
        ),
        child: FloatingActionButton(
          tooltip: t('생각 쓰기'),
          onPressed: _compose,
          backgroundColor: SgColors.accent,
          foregroundColor: SgColors.onAccent,
          elevation: 2,
          shape: const CircleBorder(),
          child: const Icon(SgIcons.write),
        ),
      ),
      bottomNavigationBar: ValueListenableBuilder(
        valueListenable: _chrome,
        builder: (context, visible, child) => AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, 1),
          duration: SgMotion.slow,
          curve: SgMotion.ease,
          child: child,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: SgColors.line)),
          ),
          child: NavigationBar(
            height: 60,
            backgroundColor: SgColors.surface,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
            selectedIndex: _tab,
            onDestinationSelected: _select,
            destinations: [
              for (final item in items)
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: item.badge > 0,
                    label: Text(item.badge > 99 ? '99+' : '${item.badge}'),
                    backgroundColor: SgColors.accent,
                    child: Icon(item.icon),
                  ),
                  selectedIcon: Icon(item.activeIcon),
                  label: item.label,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _wide(BuildContext context, Widget body, double width) {
    final expanded = width >= SgBreakpoints.wide;
    final showPanel = width >= SgBreakpoints.full;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SideNav(
                state: state,
                items: _items(),
                selected: _tab,
                onSelect: _select,
                onCompose: _compose,
                expanded: expanded,
              ),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: SgBreakpoints.column),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.symmetric(vertical: BorderSide(color: SgColors.line)),
                    ),
                    child: body,
                  ),
                ),
              ),
              if (showPanel) RightPanel(state: state, onOpenAuthor: _openAuthor),
            ],
          ),
        ),
      ),
    );
  }
}
