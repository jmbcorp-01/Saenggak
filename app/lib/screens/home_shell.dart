import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/nav.dart';
import '../data/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/right_panel.dart';
import '../widgets/shell_chrome.dart';
import '../widgets/side_nav.dart';
import 'compose_screen.dart';
import 'feed_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';

/// The signed-in app: home, notifications and profile, and the write button.
///
/// On a phone the menu is at the bottom. From [SgBreakpoints.rail] it moves to
/// the left and the timeline becomes a centered column; from
/// [SgBreakpoints.full] a panel appears on the right. Each tab keeps its own
/// page history, so opening a profile keeps the menus in place.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.state, this.checkEvery = const Duration(minutes: 1)});

  final AppState state;

  /// How often to look for new posts while the app is open.
  final Duration checkEvery;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;
  final _navigators = List.generate(3, (_) => GlobalKey<NavigatorState>());
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
  }

  @override
  void dispose() {
    _check?.cancel();
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
      } else if (i == 0) {
        _homeAgain.value++;
      }
      return;
    }
    setState(() => _tab = i);
    if (i == 1) {
      state.loadNotifications().then((_) => state.markNotificationsSeen());
    }
  }

  void _compose() => pushModal<void>(context, (_) => ComposeScreen(state: state));

  void _openAuthor(String userId) {
    final nav = _navigators[_tab].currentState;
    if (userId == state.me?.id) {
      _select(2);
      return;
    }
    nav?.push(
      MaterialPageRoute<void>(
        builder: (_) => ProfilePage(state: state, userId: userId),
      ),
    );
  }

  List<NavItem> _items() => [
    const NavItem(icon: SgIcons.home, activeIcon: SgIcons.homeActive, label: '홈'),
    NavItem(icon: SgIcons.bell, activeIcon: SgIcons.bellActive, label: '알림', badge: state.unreadNotifications),
    const NavItem(icon: SgIcons.person, activeIcon: SgIcons.personActive, label: '프로필'),
  ];

  Widget _tabs() {
    final roots = <WidgetBuilder>[
      (_) => FeedScreen(state: state, onOpenProfile: () => _select(2), homeAgain: _homeAgain),
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
          tooltip: '생각 쓰기',
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
