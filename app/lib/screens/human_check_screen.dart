import 'package:material_ui/material_ui.dart';

import '../api/backend.dart';
import '../core/human_input_formatter.dart';
import '../core/typing_session.dart';
import '../l10n/l10n.dart';
import '../theme/tokens.dart';

/// Shown when activity looks automated: the person types a short sentence by
/// hand, and the server checks the typing rhythm. Pops true once it passes.
class HumanCheckScreen extends StatefulWidget {
  const HumanCheckScreen({super.key, required this.backend, required this.lang, this.clock});

  final Backend backend;
  final String lang;
  final DateTime Function()? clock;

  @override
  State<HumanCheckScreen> createState() => _HumanCheckScreenState();
}

class _HumanCheckScreenState extends State<HumanCheckScreen> {
  late TypingSession _session;
  late HumanInputFormatter _formatter;
  final _controller = TextEditingController();
  String? _phrase;
  String? _error;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _reset();
    _controller.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reset() {
    _session = TypingSession(clock: widget.clock);
    _formatter = HumanInputFormatter(
      session: _session,
      isVoiceActive: () => false,
      onRejected: () => setState(() => _error = t('붙여넣기는 할 수 없어요. 한 글자씩 직접 써주세요.')),
    );
  }

  Future<void> _load() async {
    try {
      final phrase = await widget.backend.humanCheckPhrase(widget.lang);
      if (mounted) setState(() => _phrase = phrase);
    } catch (_) {
      if (mounted) setState(() => _error = t('연결이 불안정해요. 잠시 후 다시 시도해주세요.'));
    }
  }

  bool get _matches => _phrase != null && _controller.text.trim().toLowerCase() == _phrase!.toLowerCase();

  Future<void> _submit() async {
    if (!_matches || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.backend.passHumanCheck(_controller.text, _session);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      // Start over with a clean record, so the next try is judged on its own.
      _controller.clear();
      setState(() {
        _reset();
        _sending = false;
        _error = e is ApiException && e.code == 'not_human'
            ? t('확인하지 못했어요. 문장을 천천히 다시 써주세요.')
            : t('연결이 불안정해요. 잠시 후 다시 시도해주세요.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final phrase = _phrase;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: t('닫기'),
                icon: const Icon(SgIcons.close),
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ),
            Expanded(
              child: ListView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(SgSpace.xl, SgSpace.sm, SgSpace.xl, SgSpace.xl),
                children: [
                  Text(t('사람인지 확인할게요'), style: SgText.title),
                  const SizedBox(height: SgSpace.sm),
                  Text(t('짧은 시간에 많은 활동이 있었어요. 아래 문장을 직접 써주시면 이어서 할 수 있어요.'), style: SgText.meta),
                  const SizedBox(height: SgSpace.xl),
                  Container(
                    padding: const EdgeInsets.all(SgSpace.lg),
                    decoration: BoxDecoration(color: SgColors.band, borderRadius: BorderRadius.circular(SgRadius.md)),
                    child: phrase == null
                        ? const Center(
                            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : Text(phrase, key: const Key('check-phrase'), style: SgText.body),
                  ),
                  const SizedBox(height: SgSpace.lg),
                  Actions(
                    actions: {PasteTextIntent: DoNothingAction(consumesKey: true)},
                    child: TextField(
                      key: const Key('check-input'),
                      controller: _controller,
                      autofocus: true,
                      readOnly: _sending || phrase == null,
                      autocorrect: false,
                      enableSuggestions: false,
                      enableIMEPersonalizedLearning: false,
                      inputFormatters: [_formatter],
                      contextMenuBuilder: (context, state) => AdaptiveTextSelectionToolbar.buttonItems(
                        anchors: state.contextMenuAnchors,
                        buttonItems: state.contextMenuButtonItems
                            .where((i) => i.type != ContextMenuButtonType.paste)
                            .toList(),
                      ),
                      onSubmitted: (_) => _submit(),
                      style: SgText.body,
                      decoration: InputDecoration(
                        hintText: t('위 문장을 그대로 써주세요'),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(SgRadius.md)),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: SgSpace.md),
                    Text(_error!, style: SgText.small.copyWith(color: SgColors.accentText)),
                  ],
                  const SizedBox(height: SgSpace.xl),
                  FilledButton(
                    key: const Key('check-submit'),
                    onPressed: _matches && !_sending ? _submit : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: SgColors.ink,
                      foregroundColor: SgColors.onInk,
                      disabledBackgroundColor: SgColors.line,
                      disabledForegroundColor: SgColors.muted,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: Text(t('확인')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
