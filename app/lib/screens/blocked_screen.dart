import 'package:material_ui/material_ui.dart';

import '../data/app_state.dart';
import '../l10n/l10n.dart';
import '../models/social.dart';
import '../theme/tokens.dart';

/// The people the reader blocked, each with a way to unblock.
class BlockedScreen extends StatefulWidget {
  const BlockedScreen({super.key, required this.state});

  final AppState state;

  @override
  State<BlockedScreen> createState() => _BlockedScreenState();
}

class _BlockedScreenState extends State<BlockedScreen> {
  List<BlockedUser>? _users;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final users = await widget.state.backend.blockedUsers();
      if (mounted) setState(() => _users = users);
    } catch (_) {
      if (mounted) setState(() => _users = const []);
    }
  }

  Future<void> _unblock(BlockedUser u) async {
    try {
      await widget.state.unblock(u.id);
      if (!mounted) return;
      setState(() => _users = _users?.where((x) => x.id != u.id).toList());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('@{0} 님 차단을 풀었어요.', [u.handle]))));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('차단을 풀지 못했어요.'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = _users;
    return Scaffold(
      appBar: AppBar(title: Text(t('차단한 사람'))),
      body: users == null
          ? const Center(child: CircularProgressIndicator())
          : users.isEmpty
          ? Center(child: Text(t('차단한 사람이 없어요.'), style: SgText.small))
          : ListView(
              children: [
                for (final u in users)
                  ListTile(
                    title: Text(u.displayName),
                    subtitle: Text('@${u.handle}'),
                    trailing: OutlinedButton(onPressed: () => _unblock(u), child: Text(t('차단 풀기'))),
                  ),
              ],
            ),
    );
  }
}
