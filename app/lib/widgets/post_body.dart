import 'package:material_ui/material_ui.dart';

/// A post's text, with each blank line drawn half a line high: the writer's
/// paragraphs stay apart, and the feed stays close. Runs of blank lines in
/// older posts show as one.
class PostBody extends StatelessWidget {
  const PostBody(this.text, {super.key, required this.style});

  final String text;
  final TextStyle style;

  static final _blankLines = RegExp(r'\n[ \t　]*(?:\n[ \t　]*)+');

  @override
  Widget build(BuildContext context) {
    final paragraphs = text.trim().split(_blankLines);
    if (paragraphs.length == 1) return Text(paragraphs.single, style: style);
    final gap = (style.fontSize ?? 15) * (style.height ?? 1.4) / 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < paragraphs.length; i++) ...[
          if (i > 0) SizedBox(height: gap),
          Text(paragraphs[i], style: style),
        ],
      ],
    );
  }
}
