import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/human_check.dart';
import '../core/human_input_formatter.dart';
import '../core/typing_session.dart';
import '../core/weighted_length.dart';
import '../data/post_store.dart';
import '../models/post.dart';
import '../theme/tokens.dart';
import '../widgets/post_tile.dart';

/// Writing screen. Only hand-typed (or dictated) text gets in, and the typing
/// session is kept so the post can show its real typing time.
class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key, required this.store, this.clock});

  final PostStore store;
  final DateTime Function()? clock;

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  late final TypingSession _session = TypingSession(clock: widget.clock);
  late final HumanInputFormatter _formatter = HumanInputFormatter(
    session: _session,
    isVoiceActive: () => _voice,
    onRejected: _onPasteRejected,
  );
  final _controller = TextEditingController();
  Timer? _ticker;
  bool _voice = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onPasteRejected() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('붙여넣기는 할 수 없어요. 한 글자씩 직접 써주세요.'),
      ));
  }

  void _submit() {
    final status = WeightedLength.status(_controller.text);
    if (!status.postable) return;
    final check = HumanCheck.evaluate(_session);
    if (!check.passed) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('사람이 직접 입력한 기록으로 확인되지 않았어요. 다시 써주세요.'),
      ));
      return;
    }
    widget.store.add(Post(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      authorName: '윤서',
      authorHandle: 'yoonseo',
      authorInitial: '윤',
      avatarColor: 0xFF3B4A42,
      body: _controller.text.trim(),
      postedAgo: '방금',
      typingTime: _session.activeDuration,
      empathyCount: 0,
      isMine: true,
    ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final status = WeightedLength.status(_controller.text);
    final elapsed = _session.activeDuration;
    final timer =
        '${elapsed.inMinutes.toString().padLeft(2, '0')}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(foregroundColor: SgColors.ink),
                      child: const Text('취소', style: TextStyle(fontSize: 15)),
                    ),
                    FilledButton(
                      key: const Key('submit'),
                      onPressed: status.postable ? _submit : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: SgColors.ink,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: SgColors.outline,
                        disabledForegroundColor: Colors.white,
                        minimumSize: const Size(0, 36),
                        textStyle: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      child: const Text('게시하기'),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Avatar(
                      initial: '윤',
                      color: 0xFF3B4A42,
                      label: '내 프로필 사진',
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Actions(
                        actions: {
                          PasteTextIntent: DoNothingAction(consumesKey: true),
                        },
                        child: TextField(
                          key: const Key('thought'),
                          controller: _controller,
                          autofocus: true,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          autocorrect: false,
                          enableSuggestions: false,
                          enableIMEPersonalizedLearning: false,
                          inputFormatters: [_formatter],
                          contextMenuBuilder: _menuWithoutPaste,
                          style: const TextStyle(
                              fontSize: 19, height: 1.6, color: SgColors.ink),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: '지금 어떤 생각을 하고 있나요?',
                            hintStyle:
                                TextStyle(fontSize: 19, color: SgColors.muted),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: SgColors.line)),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: _voice ? '음성 입력 끄기' : '음성으로 입력',
                    onPressed: () => setState(() => _voice = !_voice),
                    icon: Icon(_voice ? Icons.mic : Icons.mic_none),
                    color: SgColors.accent,
                  ),
                  Text(_voice ? '음성 입력 중' : '붙여넣기 불가', style: SgText.small),
                  const Spacer(),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                        color: SgColors.accent, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(timer,
                      style: SgText.mono.copyWith(
                          fontSize: 12, color: SgColors.ink)),
                  const SizedBox(width: 14),
                  Container(width: 1, height: 24, color: SgColors.line),
                  const SizedBox(width: 14),
                  LengthRing(status: status),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuWithoutPaste(BuildContext context, EditableTextState state) {
    final items = state.contextMenuButtonItems
        .where((i) => i.type != ContextMenuButtonType.paste)
        .toList();
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: state.contextMenuAnchors,
      buttonItems: items,
    );
  }
}

/// Circle that fills as the draft grows. Turns ink once the minimum is met.
class LengthRing extends StatelessWidget {
  const LengthRing({super.key, required this.status});

  final LengthStatus status;

  @override
  Widget build(BuildContext context) {
    final String label;
    if (status.tooShort) {
      label = '길이 부족';
    } else if (status.tooLong) {
      label = '최대 길이 넘음';
    } else {
      label = '최대까지 ${status.remaining}';
    }
    return Semantics(
      label: label,
      child: CustomPaint(
        size: const Size.square(26),
        painter: _RingPainter(status),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.status);

  final LengthStatus status;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    const r = 10.0;
    final track = Paint()
      ..color = SgColors.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(center, r, track);
    final color = status.tooLong
        ? SgColors.accentText
        : status.tooShort
            ? SgColors.muted
            : SgColors.accent;
    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      -math.pi / 2,
      2 * math.pi * status.progress,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.status.units != status.units;
}
