import 'package:material_ui/material_ui.dart';

import '../data/app_state.dart';
import '../l10n/l10n.dart';
import '../models/social.dart';
import '../theme/tokens.dart';

/// Asks why, sends the report, and offers to block the person too.
/// Report a post with [postId], or the person alone without it.
Future<void> reportFlow(
  BuildContext context,
  AppState state, {
  required String userId,
  required String handle,
  String? postId,
}) async {
  final reason = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(postId != null ? t('이 글을 신고하는 이유') : t('@{0} 님을 신고하는 이유', [handle]), style: SgText.name),
          ),
          for (final e in reportReasons.entries)
            ListTile(title: Text(t(e.value)), onTap: () => Navigator.pop(context, e.key)),
        ],
      ),
    ),
  );
  if (reason == null || !context.mounted) return;
  try {
    await state.report(postId: postId, userId: userId, reason: reason);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('신고하지 못했어요. 다시 시도해주세요.'))));
    }
    return;
  }
  if (!context.mounted) return;
  final alsoBlock = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t('신고했어요')),
      content: Text(t('운영팀이 확인할게요. @{0} 님을 차단하면 서로의 글이 보이지 않고 팔로우와 공감도 할 수 없어요.', [handle])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('닫기'))),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(foregroundColor: SgColors.accentText),
          child: Text(t('차단하기')),
        ),
      ],
    ),
  );
  if (alsoBlock == true && context.mounted) await blockFlow(context, state, userId: userId, handle: handle, ask: false);
}

/// Blocks after asking (unless [ask] is false) and says so.
Future<bool> blockFlow(
  BuildContext context,
  AppState state, {
  required String userId,
  required String handle,
  bool ask = true,
}) async {
  if (ask) {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('@{0} 님을 차단할까요?', [handle])),
        content: Text(t('서로의 글이 보이지 않고, 팔로우와 공감도 할 수 없어요. 상대에게 알리지 않아요. 설정에서 언제든 풀 수 있어요.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('취소'))),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: SgColors.accentText),
            child: Text(t('차단')),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return false;
  }
  try {
    await state.block(userId);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('@{0} 님을 차단했어요.', [handle]))));
    }
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('차단하지 못했어요. 다시 시도해주세요.'))));
    }
    return false;
  }
}
