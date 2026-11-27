import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import 'symbol_mark.dart';

/// A square card of one thought, for sharing outside the app: the words as
/// typed, who wrote them (or no one, for anonymous sharing), how long the
/// typing took, and the 생각 mark. The same card is used by writers sharing
/// their own post and by admins posting to Saenggak's own accounts.
class ShareCard extends StatelessWidget {
  const ShareCard({
    super.key,
    required this.body,
    required this.typingTime,
    this.authorName,
    this.similarPeople = 0,
    this.lang = 'ko',
  });

  final String body;
  final Duration typingTime;

  /// Null for a card without a name.
  final String? authorName;

  /// Shown when three or more others had a similar thought.
  final int similarPeople;
  final String lang;

  /// Always light: a card is a picture, not part of the screen's theme.
  static const _paper = Color(0xFFFBF8F3);
  static const _ink = Color(0xFF151515);
  static const _muted = Color(0xFF6B6B6B);
  static const _accent = Color(0xFFB8361F);

  @override
  Widget build(BuildContext context) {
    final ko = lang == 'ko';
    final minutes = typingTime.inSeconds < 60 ? 1 : typingTime.inMinutes;
    final by = authorName == null
        ? (ko ? '어느 생각러의 생각' : 'A thought from Saenggak')
        : (ko ? '$authorName님의 생각' : 'A thought by $authorName');
    final typed = ko ? '직접 타이핑 $minutes분' : 'Typed by hand in $minutes min';
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, box) {
          // Everything scales with the card, so the 1080 px export matches the preview.
          final u = box.maxWidth / 360;
          return Container(
            color: _paper,
            padding: EdgeInsets.fromLTRB(30 * u, 30 * u, 30 * u, 26 * u),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SymbolMark(size: 26 * u, strokeColor: _accent, dotColor: _ink, semanticLabel: null),
                    SizedBox(width: 8 * u),
                    Text(
                      '생각',
                      style: TextStyle(
                        fontFamily: SgFonts.sans,
                        fontSize: 17 * u,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      body,
                      key: const Key('share-card-body'),
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontFamily: SgFonts.sans,
                        fontFamilyFallback: SgFonts.sansFallback,
                        fontSize: (body.characters.length > 120 ? 16 : 19) * u,
                        height: 1.7,
                        color: _ink,
                      ),
                    ),
                  ),
                ),
                if (similarPeople >= 3) ...[
                  Text(
                    ko ? '비슷한 생각을 한 사람 $similarPeople명' : '$similarPeople others had a similar thought',
                    style: TextStyle(
                      fontFamily: SgFonts.sans,
                      fontSize: 12.5 * u,
                      color: _accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 6 * u),
                ],
                Text(
                  '$by · $typed',
                  style: TextStyle(fontFamily: SgFonts.sans, fontSize: 12.5 * u, color: _muted),
                ),
                SizedBox(height: 2 * u),
                Text(
                  ko ? '사람이 직접 쓴 생각만 · saenggak.app' : 'Only hand-typed thoughts · saenggak.app',
                  style: TextStyle(fontFamily: SgFonts.sans, fontSize: 12.5 * u, color: _muted),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The card inside [key]'s boundary as a PNG, [pixels] wide.
Future<Uint8List> captureCard(GlobalKey key, {double pixels = 1080}) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: pixels / boundary.size.width);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Opens the device's share sheet with the card and a line of text. Where
/// there is no share sheet, the text is copied instead. Returns false then.
Future<bool> shareCard(BuildContext context, Uint8List png, String text) async {
  final box = context.findRenderObject() as RenderBox?;
  try {
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(png, mimeType: 'image/png', name: 'saenggak.png')],
        text: text,
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
    return result.status != ShareResultStatus.unavailable;
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: text));
    return false;
  }
}

/// The writer's own share sheet for a post they just wrote or one of theirs.
class ShareCardSheet extends StatefulWidget {
  const ShareCardSheet({
    super.key,
    required this.body,
    required this.typingTime,
    required this.authorName,
    required this.inviteUrl,
    this.similarPeople = 0,
    this.lang = 'ko',
  });

  final String body;
  final Duration typingTime;
  final String authorName;

  /// The writer's invite link, so people who see the card can join.
  final Future<String?> inviteUrl;
  final int similarPeople;
  final String lang;

  @override
  State<ShareCardSheet> createState() => _ShareCardSheetState();
}

class _ShareCardSheetState extends State<ShareCardSheet> {
  final _card = GlobalKey();
  bool _withName = true;
  bool _busy = false;

  Future<void> _share(BuildContext buttonContext) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final png = await captureCard(_card);
      final url = await widget.inviteUrl;
      final text = t('생각에서 직접 쓴 생각이에요. {0}', [url ?? 'https://saenggak.app']);
      if (!buttonContext.mounted) return;
      final shared = await shareCard(buttonContext, png, text);
      if (!shared) messenger.showSnackBar(SnackBar(content: Text(t('공유할 수 없어 초대 링크를 복사했어요.'))));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(t('카드를 만들지 못했어요. 다시 시도해주세요.'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t('공유 카드'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(t('인스타그램 스토리나 메신저에 올려 보세요. 카드에 내 초대 링크가 함께 가요.'), style: SgText.small),
            const SizedBox(height: 16),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: RepaintBoundary(
                    key: _card,
                    child: ShareCard(
                      body: widget.body,
                      typingTime: widget.typingTime,
                      authorName: _withName ? widget.authorName : null,
                      similarPeople: widget.similarPeople,
                      lang: widget.lang,
                    ),
                  ),
                ),
              ),
            ),
            SwitchListTile(
              key: const Key('share-card-name'),
              contentPadding: EdgeInsets.zero,
              title: Text(t('내 닉네임 넣기')),
              value: _withName,
              onChanged: (v) => setState(() => _withName = v),
            ),
            Builder(
              builder: (buttonContext) => FilledButton.icon(
                key: const Key('share-card-send'),
                onPressed: _busy ? null : () => _share(buttonContext),
                icon: const Icon(Icons.ios_share),
                label: Text(t('카드 공유하기')),
                style: FilledButton.styleFrom(
                  backgroundColor: SgColors.ink,
                  foregroundColor: SgColors.onInk,
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens [ShareCardSheet] from the bottom.
Future<void> openShareCard(
  BuildContext context, {
  required String body,
  required Duration typingTime,
  required String authorName,
  required Future<String?> inviteUrl,
  int similarPeople = 0,
  String lang = 'ko',
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useRootNavigator: true,
  builder: (_) => ShareCardSheet(
    body: body,
    typingTime: typingTime,
    authorName: authorName,
    inviteUrl: inviteUrl,
    similarPeople: similarPeople,
    lang: lang,
  ),
);
