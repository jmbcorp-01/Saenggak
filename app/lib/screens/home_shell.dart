import 'package:material_ui/material_ui.dart';

import '../data/app_state.dart';
import '../theme/tokens.dart';
import 'compose_screen.dart';
import 'feed_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';

/// Bottom menu (home, notifications, profile) and the write button.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.state});

  final AppState state;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  void _compose() {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => ComposeScreen(state: widget.state)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _tab,
          children: [
            FeedScreen(state: widget.state, onOpenProfile: () => setState(() => _tab = 2)),
            NotificationsScreen(state: widget.state),
            ProfileScreen(state: widget.state),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: '생각 쓰기',
        onPressed: _compose,
        backgroundColor: SgColors.accent,
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
        child: const Icon(Icons.edit_outlined),
      ),
      bottomNavigationBar: NavigationBar(
        height: 64,
        backgroundColor: SgColors.surface,
        indicatorColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          setState(() => _tab = i);
          if (i == 1) {
            widget.state.loadNotifications().then((_) => widget.state.markNotificationsSeen());
          }
        },
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: '홈'),
          NavigationDestination(
            icon: ListenableBuilder(
              listenable: widget.state,
              builder: (context, _) {
                final n = widget.state.unreadNotifications;
                return Badge(
                  isLabelVisible: n > 0,
                  label: Text(n > 99 ? '99+' : '$n'),
                  backgroundColor: SgColors.accent,
                  child: const Icon(Icons.notifications_none),
                );
              },
            ),
            selectedIcon: const Icon(Icons.notifications),
            label: '알림',
          ),
          const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: '프로필'),
        ],
      ),
    );
  }
}
