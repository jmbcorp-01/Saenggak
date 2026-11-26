import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/human_check.dart';
import '../core/human_input_formatter.dart';
import '../core/nav.dart';
import '../core/typing_session.dart';
import '../core/weighted_length.dart';
import '../data/app_state.dart';
import '../l10n/l10n.dart';
import '../models/post.dart';
import '../models/publish_outcome.dart';
import '../theme/tokens.dart';
import '../widgets/post_tile.dart';
import 'publish_result_screen.dart';

/// Writing screen. Only hand-typed (or dictated) text gets in, and the typing
/// session is kept so the post can show its real typing time.
///
/// With [editing], the post's text is filled in and only the changes are
/// recorded; the server checks the session against the change.
class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key, required this.state, this.editing, this.clock});

  final AppState state;
  final Post? editing;
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
  late final _controller = TextEditingController(text: widget.editing?.body ?? '');
  Timer? _ticker;
  bool _voice = false;
  bool _sending = false;

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
      ..showSnackBar(SnackBar(content: Text(t('붙여넣기는 할 수 없어요. 한 글자씩 직접 써주세요.'))));
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit() async {
    final text = _controller.text;
    if (!WeightedLength.status(text).postable || _sending) return;
    if (_session.events.isEmpty) {
      _say(t('바뀐 내용이 없어요.'));
      return;
    }
    if (!HumanCheck.evaluate(_session).passed) {
      _say(const Rejected(RejectReason.notHuman).message);
      return;
    }
    setState(() => _sending = true);
    final PublishOutcome outcome;
    try {
      final editing = widget.editing;
      outcome = editing == null
          ? await widget.state.publish(text, _session)
          : await widget.state.edit(editing, text, _session);
    } catch (_) {
      if (mounted) {
        setState(() => _sending = false);
        _say(const Rejected(RejectReason.network).message);
      }
      return;
    }
    if (!mounted) return;
    setState(() => _sending = false);
    switch (outcome) {
      case final Published published:
        HapticFeedback.mediumImpact();
        await Navigator.of(context).pushReplacement(
          modalRoute<void>(
            context,
            (_) => PublishResultScreen(
              outcome: published,
              body: text.trim(),
              edited: widget.editing != null,
              daysToFollow: widget.state.me?.daysToFollow ?? 10,
            ),
            maxHeight: 760,
          ),
        );
      case final Rejected rejected:
        // The draft stays so the writer can change it and try again.
        _say(rejected.message);
    }
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
                      child: Text(t('취소'), style: TextStyle(fontSize: 15)),
                    ),
                    FilledButton(
                      key: const Key('submit'),
                      onPressed: status.postable && !_sending ? _submit : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: SgColors.ink,
                        foregroundColor: SgColors.onInk,
                        // Muted text on a light fill stays readable while disabled.
                        disabledBackgroundColor: SgColors.line,
                        disabledForegroundColor: SgColors.muted,
                        minimumSize: const Size(0, 36),
                        textStyle: SgText.label(size: 15, weight: FontWeight.w700),
                      ),
                      child: _sending
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: SgColors.onInk),
                            )
                          : Text(widget.editing == null ? t('게시하기') : t('수정하기')),
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
                    Avatar(
                      initial: widget.state.me?.initial ?? '?',
                      color: avatarPalette[(widget.state.me?.id.hashCode ?? 0).abs() % avatarPalette.length],
                      label: t('내 프로필 사진'),
                      photoUrl: widget.state.me?.photoUrl,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Actions(
                        actions: {PasteTextIntent: DoNothingAction(consumesKey: true)},
                        child: TextField(
                          key: const Key('thought'),
                          controller: _controller,
                          autofocus: true,
                          readOnly: _sending,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          autocorrect: false,
                          enableSuggestions: false,
                          enableIMEPersonalizedLearning: false,
                          inputFormatters: [_formatter],
                          contextMenuBuilder: _menuWithoutPaste,
                          style: TextStyle(fontSize: 19, height: 1.6, color: SgColors.ink),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: t('지금 어떤 생각을 하고 있나요?'),
                            hintStyle: TextStyle(fontSize: 19, color: SgColors.muted),
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
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: SgColors.line)),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: _voice ? t('음성 입력 끄기') : t('음성으로 입력'),
                    onPressed: () => setState(() => _voice = !_voice),
                    icon: Icon(_voice ? Icons.mic : Icons.mic_none),
                    color: SgColors.accent,
                  ),
                  Text(_voice ? t('음성 입력 중') : t('붙여넣기 불가'), style: SgText.small),
                  const Spacer(),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(color: SgColors.accent, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(timer, style: SgText.mono.copyWith(fontSize: 12, color: SgColors.ink)),
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
    final items = state.contextMenuButtonItems.where((i) => i.type != ContextMenuButtonType.paste).toList();
    return AdaptiveTextSelectionToolbar.buttonItems(anchors: state.contextMenuAnchors, buttonItems: items);
  }
}

/// Circle that fills as the draft grows. Turns ink once the minimum is met.
class LengthRing extends StatelessWidget {
  const LengthRing({super.key, required this.status});

  final LengthStatus status;

  @override
  Widget build(BuildContext context) {
    // Words only when the draft cannot be posted, so the writer knows why the
    // post button is off without watching a number while writing.
    final String? hint = status.units == 0
        ? null
        : status.tooShort
        ? t('조금 더 써주세요')
        : status.tooLong
        ? t('조금 줄여주세요')
        : null;
    final label = status.tooShort
        ? t('길이 부족')
        : status.tooLong
        ? t('최대 길이 넘음')
        : t('최대까지 {0}', [status.remaining]);
    return Semantics(
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hint != null) ...[
            ExcludeSemantics(
              child: Text(
                hint,
                style: SgText.small.copyWith(color: status.tooLong ? SgColors.accentText : SgColors.muted),
              ),
            ),
            const SizedBox(width: 8),
          ],
          CustomPaint(size: const Size.square(26), painter: _RingPainter(status)),
        ],
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
    canvas.drawArc(Rect.fromCircle(center: center, radius: r), -math.pi / 2, 2 * math.pi * status.progress, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.status.units != status.units;
}
