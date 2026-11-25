import 'package:material_ui/material_ui.dart';

import '../data/app_state.dart';
import '../models/post.dart';
import '../screens/compose_screen.dart';
import '../screens/profile_screen.dart';
import '../theme/tokens.dart';
import 'post_tile.dart';

/// A [PostTile] wired to the app: 공감, the author's profile, edit and delete.
class ConnectedPostTile extends StatelessWidget {
  const ConnectedPostTile({super.key, required this.state, required this.post, this.openAuthor = true});

  final AppState state;
  final Post post;

  /// False on the author's own profile page, where the link would go nowhere.
  final bool openAuthor;

  @override
  Widget build(BuildContext context) {
    return PostTile(
      post: post,
      now: state.clock(),
      onEmpathy: () => state.toggleEmpathy(post),
      onOpenAuthor: openAuthor
          ? () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(backgroundColor: SgColors.surface, surfaceTintColor: Colors.transparent),
                  body: ProfileScreen(state: state, userId: post.authorId),
                ),
              ),
            )
          : null,
      onEdit: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => ComposeScreen(state: state, editing: post),
        ),
      ),
      onDelete: () => confirmDelete(context, state, post),
    );
  }
}

Future<void> confirmDelete(BuildContext context, AppState state, Post post) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('이 글을 삭제할까요?'),
      content: const Text('삭제한 글은 되돌릴 수 없어요. 받은 공감과 처음 쓴 표현 기록도 함께 사라져요.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
        TextButton(
          key: const Key('confirm-delete'),
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(foregroundColor: SgColors.accentText),
          child: const Text('삭제'),
        ),
      ],
    ),
  );
  if (yes != true || !context.mounted) return;
  try {
    await state.delete(post);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('삭제하지 못했어요. 다시 시도해주세요.')));
    }
  }
}
