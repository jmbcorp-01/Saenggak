import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';

/// Grey shapes in the layout of a timeline row, with a light sweeping
/// across them, shown while the first posts load.
class PostSkeletonList extends StatefulWidget {
  const PostSkeletonList({super.key, this.count = 5});

  final int count;

  @override
  State<PostSkeletonList> createState() => _PostSkeletonListState();
}

class _PostSkeletonListState extends State<PostSkeletonList> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: '글을 불러오는 중',
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) {
            final base = SgColors.skeleton;
            final shine = Color.lerp(base, SgColors.surface, 0.55)!;
            final t = reduce ? 0.5 : _c.value;
            return ShaderMask(
              blendMode: BlendMode.srcATop,
              shaderCallback: (rect) => LinearGradient(
                begin: Alignment(-1.0 + 3 * t - 0.6, -0.2),
                end: Alignment(-1.0 + 3 * t + 0.6, 0.2),
                colors: [base, shine, base],
              ).createShader(rect),
              child: child,
            );
          },
          child: Column(children: [for (var i = 0; i < widget.count; i++) _SkeletonRow(lines: 2 + i % 2)]),
        ),
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({required this.lines});

  final int lines;

  @override
  Widget build(BuildContext context) {
    Widget bar(double width, {double height = 12}) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: SgColors.skeleton, borderRadius: BorderRadius.circular(6)),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(SgSpace.lg, SgSpace.lg, SgSpace.lg, SgSpace.lg),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: SgColors.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: SgColors.skeleton, shape: BoxShape.circle),
          ),
          const SizedBox(width: SgSpace.md),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  bar(c.maxWidth * 0.45),
                  const SizedBox(height: 14),
                  for (var i = 0; i < lines; i++) ...[
                    bar(i == lines - 1 ? c.maxWidth * 0.6 : c.maxWidth),
                    const SizedBox(height: 9),
                  ],
                  const SizedBox(height: 8),
                  bar(48, height: 10),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
