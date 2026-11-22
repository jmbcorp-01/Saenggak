import 'package:material_ui/material_ui.dart';

import '../data/post_store.dart';
import '../theme/tokens.dart';
import 'compose_screen.dart';
import 'feed_screen.dart';
import 'profile_screen.dart';

/// Bottom menu (home, notifications, profile) and the write button.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.store});

  final PostStore store;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  void _compose() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => ComposeScreen(store: widget.store),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _tab,
          children: [
            FeedScreen(
              store: widget.store,
              onOpenProfile: () => setState(() => _tab = 2),
            ),
            const Center(child: Text('아직 알림이 없어요.', style: SgText.small)),
            ProfileScreen(store: widget.store, onEdit: _compose),
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
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: '홈'),
          NavigationDestination(
              icon: Icon(Icons.notifications_none),
              selectedIcon: Icon(Icons.notifications),
              label: '알림'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: '프로필'),
        ],
      ),
    );
  }
}
