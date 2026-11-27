import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../api/backend.dart';
import '../l10n/l10n.dart';
import '../models/growth.dart';
import '../theme/tokens.dart';
import '../widgets/share_card.dart';

/// The admin pages for growth without ad spend: the numbers by day, the
/// promo agent's queue, the daily questions, link codes and the audit log.

void _toast(BuildContext context, String text) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(text)));

String _failure(Object e) =>
    e is ApiException && e.code == 'forbidden' ? t('관리자 권한이 없어요. 다시 로그인해 보세요.') : t('처리하지 못했어요. 다시 시도해주세요.');

const _site = String.fromEnvironment('SITE_URL', defaultValue: 'https://saenggak.app');

String _day(DateTime d) {
  final l = d.toLocal();
  return '${l.month}/${l.day} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

/// Loads once, shows a spinner or the error until then, and reloads on pull.
class _Loader<T> extends StatefulWidget {
  const _Loader({super.key, required this.load, required this.builder});

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T value, Future<void> Function() reload) builder;

  @override
  State<_Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<_Loader<T>> {
  T? _value;
  bool _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final v = await widget.load();
      if (mounted) setState(() => (_value = v, _loaded = true, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = _failure(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!, style: SgText.small));
    }
    return RefreshIndicator(onRefresh: _reload, child: widget.builder(context, _value as T, _reload));
  }
}

// ---------------------------------------------------------------------------
// Dashboard

/// Sign-ups, posts and active people by day, how many come back, and where
/// people came from.
class AdminDashboardTab extends StatelessWidget {
  const AdminDashboardTab({super.key, required this.backend});

  final Backend backend;

  @override
  Widget build(BuildContext context) {
    return _Loader<Dashboard>(
      load: () => backend.adminDashboard(days: 30),
      builder: (context, d, _) {
        final days = d.days.reversed.take(14).toList();
        final peak = days.fold<int>(1, (m, x) => x.activePeople > m ? x.activePeople : m);
        String rate(Retention r) => r.rate == null ? '-' : '${(r.rate! * 100).round()}%';
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(t('다시 찾아온 사람'), style: SgText.meta),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final (label, r) in [('D1', d.d1), ('D7', d.d7), ('D30', d.d30)])
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(label, style: SgText.small),
                            Text(rate(r), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                            Text(t('{0}명 중', [r.cohort]), style: SgText.small),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text(t('최근 14일'), style: SgText.meta),
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(width: 56, child: Text(t('날짜'), style: SgText.small)),
                Expanded(child: Text(t('활동한 사람'), style: SgText.small)),
                SizedBox(
                  width: 40,
                  child: Text(t('가입'), style: SgText.small, textAlign: TextAlign.end),
                ),
                SizedBox(
                  width: 40,
                  child: Text(t('글'), style: SgText.small, textAlign: TextAlign.end),
                ),
                SizedBox(
                  width: 40,
                  child: Text(t('공감'), style: SgText.small, textAlign: TextAlign.end),
                ),
              ],
            ),
            for (final x in days)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(width: 56, child: Text(x.day.length >= 10 ? x.day.substring(5) : x.day)),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: FractionallySizedBox(
                              widthFactor: x.activePeople / peak,
                              child: Container(height: 10, color: SgColors.accent),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text('${x.activePeople}', style: SgText.small),
                        ],
                      ),
                    ),
                    SizedBox(width: 40, child: Text('${x.signups}', textAlign: TextAlign.end)),
                    SizedBox(width: 40, child: Text('${x.posts}', textAlign: TextAlign.end)),
                    SizedBox(width: 40, child: Text('${x.empathies}', textAlign: TextAlign.end)),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            Text(t('어디서 왔나요 (최근 30일)'), style: SgText.meta),
            for (final s in d.sources)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_channelName(s.channel)),
                subtitle: Text(t('일주일 뒤에도 쓰는 사람 {0}명', [s.active7])),
                trailing: Text(t('가입 {0}', [s.signups]), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
          ],
        );
      },
    );
  }
}

String _channelName(String c) => switch (c) {
  'invite' => t('친구 초대'),
  'direct' => t('직접 (코드 없음)'),
  'instagram' => t('인스타그램'),
  'threads' => t('스레드'),
  'community' => t('커뮤니티'),
  'web' => t('공개 웹페이지'),
  'press' => t('기사'),
  'event' => t('행사'),
  _ => c,
};

// ---------------------------------------------------------------------------
// Promo queue

/// Posts the promo agent picked for Saenggak's own accounts. Nothing is
/// posted until an admin approves it here.
class AdminPromoTab extends StatefulWidget {
  const AdminPromoTab({super.key, required this.backend});

  final Backend backend;

  @override
  State<AdminPromoTab> createState() => _AdminPromoTabState();
}

class _AdminPromoTabState extends State<AdminPromoTab> {
  String _tab = 'pending';
  int _version = 0;
  bool _picking = false;

  void _reload() => setState(() => _version++);

  Future<void> _pick() async {
    setState(() => _picking = true);
    try {
      final added = await widget.backend.runPromoPick();
      if (!mounted) return;
      _toast(context, added == 0 ? t('새로 고를 만한 글이 없어요.') : t('{0}개를 골랐어요.', [added]));
      _reload();
    } catch (e) {
      if (mounted) _toast(context, _failure(e));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<String>(
                  key: const Key('promo-tabs'),
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: 'pending', label: Text(t('승인 대기'))),
                    ButtonSegment(value: 'scheduled', label: Text(t('예약'))),
                    ButtonSegment(value: 'done', label: Text(t('지난 것'))),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (v) => setState(() => _tab = v.first),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                key: const Key('promo-pick'),
                tooltip: t('지금 고르기'),
                onPressed: _picking ? null : _pick,
                icon: const Icon(Icons.auto_awesome_outlined),
              ),
            ],
          ),
        ),
        Expanded(
          child: _Loader<PromoPage>(
            key: ValueKey('$_tab-$_version'),
            load: () => widget.backend.promoItems(_tab),
            builder: (context, page, reload) => ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text(
                  page.channels.isEmpty
                      ? t('연결된 SNS 계정이 없어요. 승인한 글은 카드를 내려받아 직접 올려 주세요.')
                      : t('자동으로 올리는 계정: {0}', [page.channels.map(_channelName).join(', ')]),
                  style: SgText.small,
                ),
                const SizedBox(height: 12),
                if (page.items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 80),
                    child: Center(child: Text(t('여기에는 아직 없어요.'), style: SgText.small)),
                  ),
                for (final item in page.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _PromoCard(key: ValueKey(item.id), backend: widget.backend, item: item, onChanged: _reload),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PromoCard extends StatefulWidget {
  const _PromoCard({super.key, required this.backend, required this.item, required this.onChanged});

  final Backend backend;
  final PromoItem item;
  final VoidCallback onChanged;

  @override
  State<_PromoCard> createState() => _PromoCardState();
}

class _PromoCardState extends State<_PromoCard> {
  final _card = GlobalKey();
  late final _caption = TextEditingController(text: widget.item.caption);
  bool _busy = false;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() step, String done) async {
    setState(() => _busy = true);
    try {
      await step();
      if (!mounted) return;
      _toast(context, done);
      widget.onChanged();
    } catch (e) {
      if (mounted) _toast(context, _failure(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve() => _run(() async {
    final png = await captureCard(_card);
    await widget.backend.decidePromo(widget.item.id, approve: true, caption: _caption.text.trim(), png: png);
  }, t('승인했어요. 저녁 9시에 올라가요.'));

  Future<void> _skip() => _run(() => widget.backend.decidePromo(widget.item.id, approve: false), t('건너뛰었어요.'));

  Future<void> _mark(String status) => _run(
    () => widget.backend.markPromo(widget.item.id, status),
    status == 'posted' ? t('올린 것으로 표시했어요.') : t('내린 것으로 표시했어요.'),
  );

  Future<void> _copyCaption() async {
    await Clipboard.setData(ClipboardData(text: _caption.text));
    if (mounted) _toast(context, t('캡션을 복사했어요.'));
  }

  String _statusLabel(String s) => switch (s) {
    'pending' => t('승인 대기'),
    'approved' => t('예약됨'),
    'failed' => t('올리지 못함'),
    'takedown' => t('직접 지워야 함'),
    'posted' => t('올라감'),
    'skipped' => t('건너뜀'),
    'withdrawn' => t('내림'),
    _ => s,
  };

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final post = item.post;
    final pending = item.status == 'pending';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(_statusLabel(item.status), style: const TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                if (post != null)
                  Text('@${post.authorHandle} · ${t('공감 {0}', [post.empathyCount])}', style: SgText.small),
              ],
            ),
            const SizedBox(height: 8),
            if (post == null)
              Text(t('글이 지워졌거나 글쓴이가 공유를 껐어요.'), style: SgText.small)
            else if (pending)
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: RepaintBoundary(
                    key: _card,
                    child: ShareCard(
                      body: post.body,
                      typingTime: Duration(milliseconds: post.typingMs),
                      authorName: post.authorName,
                      lang: post.lang,
                    ),
                  ),
                ),
              )
            else
              Text(post.body, maxLines: 4, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            if (pending)
              TextField(
                key: const Key('promo-caption'),
                controller: _caption,
                maxLines: 4,
                minLines: 2,
                maxLength: 400,
                decoration: InputDecoration(labelText: t('캡션')),
              )
            else ...[
              Text(item.caption, style: SgText.small),
              const SizedBox(height: 6),
              if (item.scheduledFor != null) Text(t('예약 시각 {0}', [_day(item.scheduledFor!)]), style: SgText.small),
              if (item.posted.isNotEmpty)
                Text(t('올린 곳: {0}', [item.posted.keys.map(_channelName).join(', ')]), style: SgText.small),
              if (item.error != null) Text(item.error!, style: TextStyle(fontSize: 13, color: SgColors.accentText)),
              Text(t('링크 {0} · 클릭 {1} · 가입 {2}', [item.linkCode, item.clicks, item.signups]), style: SgText.small),
            ],
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                if (pending) ...[
                  TextButton(onPressed: _busy ? null : _skip, child: Text(t('건너뛰기'))),
                  FilledButton(
                    key: const Key('promo-approve'),
                    onPressed: _busy || post == null ? null : _approve,
                    style: FilledButton.styleFrom(backgroundColor: SgColors.ink, foregroundColor: SgColors.onInk),
                    child: Text(t('승인')),
                  ),
                ] else ...[
                  TextButton(onPressed: _copyCaption, child: Text(t('캡션 복사'))),
                  if (item.cardUrl != null)
                    TextButton(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: item.cardUrl!));
                        if (context.mounted) _toast(context, t('카드 이미지 주소를 복사했어요.'));
                      },
                      child: Text(t('카드 주소 복사')),
                    ),
                  if (item.status == 'approved' || item.status == 'failed')
                    TextButton(onPressed: _busy ? null : () => _mark('posted'), child: Text(t('직접 올렸어요'))),
                  if (item.status == 'posted' || item.status == 'takedown' || item.status == 'approved')
                    TextButton(
                      onPressed: _busy ? null : () => _mark('withdrawn'),
                      style: TextButton.styleFrom(foregroundColor: SgColors.accentText),
                      child: Text(item.status == 'takedown' ? t('지웠어요') : t('내리기')),
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Daily questions

/// The questions the agent drafts each week, shown above the editor only
/// once an admin approves them.
class AdminQuestionsTab extends StatelessWidget {
  const AdminQuestionsTab({super.key, required this.backend});

  final Backend backend;

  Future<void> _edit(BuildContext context, AdminQuestion q, Future<void> Function() reload) async {
    final ko = TextEditingController(text: q.textKo);
    final en = TextEditingController(text: q.textEn);
    final approve = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(q.day),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ko,
              maxLength: 80,
              decoration: const InputDecoration(labelText: '한국어'),
            ),
            TextField(
              controller: en,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'English'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('초안으로 저장'))),
          FilledButton(
            key: const Key('question-approve'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('승인')),
          ),
        ],
      ),
    );
    if (approve == null || !context.mounted) return;
    try {
      await backend.saveQuestion(q.day, textKo: ko.text.trim(), textEn: en.text.trim(), approve: approve);
      if (context.mounted) _toast(context, approve ? t('승인했어요. 그날 글쓰기 화면에 보여요.') : t('초안으로 저장했어요.'));
      await reload();
    } catch (e) {
      if (context.mounted) _toast(context, _failure(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Loader<List<AdminQuestion>>(
      load: backend.adminQuestions,
      builder: (context, questions, reload) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(t('승인한 질문만 그날 글쓰기 화면에 보여요. 초안은 매주 월요일 아침에 만들어져요.'), style: SgText.small),
          const SizedBox(height: 8),
          if (questions.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 80),
              child: Center(child: Text(t('아직 질문이 없어요.'), style: SgText.small)),
            ),
          for (final q in questions)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(q.textKo),
              subtitle: Text('${q.day} · ${q.textEn}'),
              trailing: q.approved
                  ? Icon(Icons.check_circle, color: SgColors.accent)
                  : Text(t('초안'), style: SgText.small),
              onTap: () => _edit(context, q, reload),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Link codes

/// Every link code with its clicks and sign-ups, and new codes for a
/// community post or an event.
class AdminLinksTab extends StatelessWidget {
  const AdminLinksTab({super.key, required this.backend});

  final Backend backend;

  Future<void> _create(BuildContext context, Future<void> Function() reload) async {
    final code = TextEditingController();
    final label = TextEditingController();
    var channel = 'community';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: Text(t('새 유입 링크')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('link-code'),
                controller: code,
                autocorrect: false,
                maxLength: 32,
                decoration: InputDecoration(labelText: t('코드 (영문 소문자, 숫자, -)'), helperText: '$_site/i/…'),
              ),
              DropdownButtonFormField<String>(
                initialValue: channel,
                decoration: InputDecoration(labelText: t('채널')),
                items: [for (final c in linkChannels) DropdownMenuItem(value: c, child: Text(_channelName(c)))],
                onChanged: (v) => set(() => channel = v ?? channel),
              ),
              TextField(
                controller: label,
                maxLength: 60,
                decoration: InputDecoration(labelText: t('메모 (선택)')),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('취소'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t('만들기'))),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final c = code.text.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9][a-z0-9-]{2,31}$').hasMatch(c)) {
      _toast(context, t('코드는 영문 소문자, 숫자, - 로 3자에서 32자 사이예요.'));
      return;
    }
    try {
      await backend.createLink(code: c, channel: channel, label: label.text.trim());
      await Clipboard.setData(ClipboardData(text: '$_site/i/$c'));
      if (context.mounted) _toast(context, t('링크를 만들고 복사했어요.'));
      await reload();
    } on ApiException catch (e) {
      if (context.mounted) _toast(context, e.code == 'taken' ? t('이미 있는 코드예요.') : _failure(e));
    } catch (e) {
      if (context.mounted) _toast(context, _failure(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Loader<List<LinkStat>>(
      load: backend.linkStats,
      builder: (context, links, reload) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const Key('link-new'),
              onPressed: () => _create(context, reload),
              icon: const Icon(Icons.add_link),
              label: Text(t('새 링크')),
            ),
          ),
          for (final l in links)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(switch (l.code) {
                '*' when l.channel == 'invite' => t('친구 초대 전체'),
                '*' => t('홍보 글 전체'),
                _ => l.label.isEmpty ? l.code : '${l.label} · ${l.code}',
              }),
              subtitle: Text(
                t('{0} · 클릭 {1} · 가입 {2} · 일주일 뒤 {3}', [_channelName(l.channel), l.clicks, l.signups, l.active7]),
              ),
              trailing: l.code == '*' ? null : const Icon(Icons.copy, size: 18),
              onTap: l.code == '*'
                  ? null
                  : () async {
                      await Clipboard.setData(ClipboardData(text: '$_site/i/${l.code}'));
                      if (context.mounted) _toast(context, t('링크를 복사했어요.'));
                    },
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Audit log

/// What each admin did, newest first.
class AdminAuditTab extends StatelessWidget {
  const AdminAuditTab({super.key, required this.backend});

  final Backend backend;

  static String _action(String a) => switch (a) {
    'remove_post' => t('글 내림'),
    'publish' => t('검토 후 올림'),
    'keep_blocked' => t('검토 후 차단 유지'),
    'resolve_report' => t('신고 처리'),
    'suspend' => t('정지'),
    'unsuspend' => t('정지 풀기'),
    'remove_photo' => t('사진 지움'),
    'promo_approve' => t('홍보 승인'),
    'promo_skip' => t('홍보 건너뜀'),
    'promo_posted' => t('홍보 직접 올림'),
    'promo_withdrawn' => t('홍보 내림'),
    'link_code' => t('유입 링크 만듦'),
    'question_approved' => t('질문 승인'),
    'question_draft' => t('질문 초안 저장'),
    _ => a,
  };

  @override
  Widget build(BuildContext context) {
    return _Loader<List<AuditEntry>>(
      load: () => backend.adminAudit(),
      builder: (context, entries, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 80),
              child: Center(child: Text(t('기록이 없어요.'), style: SgText.small)),
            ),
          for (final e in entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_action(e.action)),
              subtitle: Text(
                ['@${e.adminHandle ?? '-'}', _day(e.at), e.targetId, if (e.note.isNotEmpty) e.note].join(' · '),
              ),
            ),
        ],
      ),
    );
  }
}
