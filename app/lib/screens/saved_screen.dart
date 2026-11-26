import 'package:material_ui/material_ui.dart';

import '../data/app_state.dart';
import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import '../widgets/post_actions.dart';

/// Posts the reader saved to read again, newest saved first.
class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key, required this.state});

  final AppState state;

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await widget.state.loadSaved();
    } catch (_) {
      _failed = true;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return Scaffold(
      appBar: AppBar(title: Text(t('저장한 글'))),
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          if (_loading && state.saved.isEmpty) return const Center(child: CircularProgressIndicator());
          final empty = _failed ? t('저장한 글을 불러오지 못했어요.') : t('저장한 글이 없어요. 글의 메뉴에서 저장할 수 있어요.');
          return RefreshIndicator(
            onRefresh: _load,
            child: state.saved.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 160),
                      Center(
                        child: Text(empty, style: SgText.small, textAlign: TextAlign.center),
                      ),
                    ],
                  )
                : ListView(
                    children: [for (final post in state.saved) ConnectedPostTile(state: state, post: post)],
                  ),
          );
        },
      ),
    );
  }
}
