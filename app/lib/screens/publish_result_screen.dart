import 'package:material_ui/material_ui.dart';

import '../models/publish_outcome.dart';
import '../theme/tokens.dart';
import '../widgets/post_tile.dart';
import '../widgets/symbol_mark.dart';
import 'profile_screen.dart';

/// Shown right after posting, and only then: how many people had a similar
/// thought, and the phrases this post used first. Showing these while writing
/// would invite writing toward them.
class PublishResultScreen extends StatelessWidget {
  const PublishResultScreen({
    super.key,
    required this.outcome,
    required this.body,
    this.edited = false,
    this.daysToFollow = 10,
  });

  final Published outcome;
  final String body;
  final bool edited;
  final int daysToFollow;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: SgColors.surface,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(tooltip: '닫기', icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            Row(
              children: [
                Text(
                  edited ? '고쳐서 올렸어요' : '올렸어요',
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.6),
                ),
                const Spacer(),
                const SymbolMark(size: 26, semanticLabel: null),
              ],
            ),
            const SizedBox(height: 6),
            TypingTimeLabel(duration: outcome.typingTime),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.only(left: 14),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: SgColors.line, width: 3)),
              ),
              child: Text.rich(
                TextSpan(children: highlightPhrases(body, outcome.firstPhrases)),
                key: const Key('result-body'),
                style: SgText.body.copyWith(fontSize: 16.5),
              ),
            ),
            const SizedBox(height: 28),
            _SimilarCard(outcome: outcome),
            if (outcome.firstPhrases.isNotEmpty) ...[
              const SizedBox(height: 28),
              const Text('처음 쓴 표현', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('지금까지 아무도 쓰지 않았던 표현이에요.', style: SgText.small),
              const SizedBox(height: 8),
              for (final phrase in outcome.firstPhrases)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: SgColors.line)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('“$phrase”', style: TextStyle(fontSize: 16, color: SgColors.ink)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          border: Border.all(color: SgColors.accentText),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '처음 씀',
                          style: SgText.label(size: 12, weight: FontWeight.w500).copyWith(color: SgColors.accentText),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 28),
            if (outcome.followUnlocked)
              Text('팔로우가 열려 있어요. 마음에 드는 글쓴이를 팔로우해보세요.', style: SgText.small)
            else
              FollowProgress(days: outcome.writingDays, total: daysToFollow),
            const SizedBox(height: 28),
            FilledButton(
              key: const Key('result-done'),
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: SgColors.ink,
                foregroundColor: SgColors.onInk,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                textStyle: SgText.label(size: 16, weight: FontWeight.w700),
              ),
              child: const Text('피드로'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SimilarCard extends StatelessWidget {
  const _SimilarCard({required this.outcome});

  final Published outcome;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('similar-card'),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(color: SgColors.band, borderRadius: BorderRadius.circular(14)),
      child: outcome.showSimilar
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${outcome.similarPeople}',
                        style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                          letterSpacing: -1,
                        ),
                      ),
                      const TextSpan(
                        text: ' 명',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  semanticsLabel: '비슷한 생각을 한 사람 ${outcome.similarPeople}명',
                ),
                const SizedBox(height: 4),
                Text(
                  '비슷한 생각을 한 사람이 있어요',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: SgColors.ink),
                ),
                const SizedBox(height: 8),
                Text('뜻이 가까운 글을 쓴 다른 사람 수예요. 누가 썼는지는 보여주지 않아요.', style: SgText.small),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '아직 비슷한 생각이 없어요',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: SgColors.ink),
                ),
                SizedBox(height: 8),
                Text('비슷한 글을 쓴 사람이 3명이 넘으면 여기에 숫자로 보여드려요.', style: SgText.small),
              ],
            ),
    );
  }
}

/// The body with each first-used phrase underlined where it appears.
/// Phrases come back with edge punctuation removed, so they are found as
/// plain substrings; a phrase that cannot be found is simply not marked.
List<InlineSpan> highlightPhrases(String body, List<String> phrases) {
  final lower = body.toLowerCase();
  final ranges = <(int, int)>[];
  for (final p in phrases) {
    final at = lower.indexOf(p.toLowerCase());
    if (at < 0) continue;
    final range = (at, at + p.length);
    if (ranges.any((r) => range.$1 < r.$2 && r.$1 < range.$2)) continue;
    ranges.add(range);
  }
  ranges.sort((a, b) => a.$1.compareTo(b.$1));

  final spans = <InlineSpan>[];
  var pos = 0;
  for (final (start, end) in ranges) {
    if (start > pos) spans.add(TextSpan(text: body.substring(pos, start)));
    spans.add(
      TextSpan(
        text: body.substring(start, end),
        style: TextStyle(
          decoration: TextDecoration.underline,
          decorationColor: SgColors.accent,
          decorationThickness: 2,
        ),
      ),
    );
    pos = end;
  }
  if (pos < body.length) spans.add(TextSpan(text: body.substring(pos)));
  return spans;
}
