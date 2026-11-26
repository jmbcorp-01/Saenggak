import 'package:material_ui/material_ui.dart';

import '../data/app_state.dart';
import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import '../widgets/post_actions.dart';

/// One post on its own page, as opened from a shared link.
class PostScreen extends StatefulWidget {
  const PostScreen({super.key, required this.state, required this.postId});

  final AppState state;
  final String postId;

  @override
  State<PostScreen> createState() => _PostScreenState();
}

class _PostScreenState extends State<PostScreen> {
  bool _missing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await widget.state.open(widget.postId);
    } catch (_) {
      if (mounted) setState(() => _missing = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return Scaffold(
      appBar: AppBar(title: Text(t('생각 한 편'))),
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final post = state.opened.where((p) => p.id == widget.postId).firstOrNull;
          if (post != null) {
            return ListView(
              children: [ConnectedPostTile(state: state, post: post)],
            );
          }
          if (_missing) {
            return Center(child: Text(t('글을 찾을 수 없어요. 이미 삭제됐을 수 있어요.'), style: SgText.small));
          }
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }
}
