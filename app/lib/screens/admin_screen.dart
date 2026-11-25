import 'package:material_ui/material_ui.dart';

import '../api/backend.dart';
import '../data/app_state.dart';
import '../models/admin.dart';
import '../models/post.dart' show avatarPalette, timeAgo;
import '../theme/tokens.dart';
import '../widgets/post_tile.dart' show Avatar;

/// The admin pages: posts the filter held, people (search, suspend, remove
/// photo) and basic numbers. Only shown to people in the admins group; the
/// server checks the group again on every request.
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('관리자'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '검토 대기'),
              Tab(text: '사람'),
              Tab(text: '통계'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ReviewTab(backend: state.backend),
            _UsersTab(backend: state.backend, myId: state.me?.id),
            _StatsTab(backend: state.backend),
          ],
        ),
      ),
    );
  }
}

void _toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

String _failure(Object e) =>
    e is ApiException && e.code == 'forbidden' ? '관리자 권한이 없어요. 다시 로그인해 보세요.' : '처리하지 못했어요. 다시 시도해주세요.';

/// Asks for an optional note (a reason) before an action.
Future<String?> askNote(BuildContext context, {required String title, required String action}) {
  final note = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: note,
        autofocus: true,
        maxLength: 200,
        decoration: const InputDecoration(labelText: '사유 (기록용)'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
        TextButton(
          onPressed: () => Navigator.pop(context, note.text.trim()),
          style: TextButton.styleFrom(foregroundColor: SgColors.accentText),
          child: Text(action),
        ),
      ],
    ),
  );
}

class _ReviewTab extends StatefulWidget {
  const _ReviewTab({required this.backend});

  final Backend backend;

  @override
  State<_ReviewTab> createState() => _ReviewTabState();
}

class _ReviewTabState extends State<_ReviewTab> {
  List<ReviewItem>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await widget.backend.reviewQueue();
      if (mounted) setState(() => (_items = items, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = _failure(e));
    }
  }

  Future<void> _decide(ReviewItem item, bool publish) async {
    try {
      await widget.backend.reviewPost(item.id, publish: publish);
      if (!mounted) return;
      setState(() => _items = _items?.where((i) => i.id != item.id).toList());
      _toast(context, publish ? '피드에 올렸어요.' : '차단을 유지했어요.');
    } catch (e) {
      if (mounted) _toast(context, _failure(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null) {
      return Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!, style: SgText.small));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: items.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 120),
                Center(child: Text('검토할 글이 없어요.', style: SgText.small)),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final item = items[i];
                return Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item.authorName} @${item.authorHandle} · ${timeAgo(item.createdAt, DateTime.now())}',
                          style: SgText.meta,
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          children: [
                            Chip(label: Text(blockedReasonName(item.blockedReason))),
                            for (final issue in item.issues) Chip(label: Text('입력: $issue')),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(item.body, style: const TextStyle(fontSize: 15, height: 1.5)),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            OutlinedButton(onPressed: () => _decide(item, false), child: const Text('차단 유지')),
                            const SizedBox(width: 8),
                            FilledButton(onPressed: () => _decide(item, true), child: const Text('피드에 올리기')),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _UsersTab extends StatefulWidget {
  const _UsersTab({required this.backend, required this.myId});

  final Backend backend;
  final String? myId;

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  final _query = TextEditingController();
  List<AdminUser>? _users;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    try {
      final users = await widget.backend.searchUsers(_query.text.trim());
      if (mounted) setState(() => (_users = users, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = _failure(e));
    }
  }

  Future<void> _act(Future<void> Function() step, String done) async {
    try {
      await step();
      if (!mounted) return;
      _toast(context, done);
      await _search();
    } catch (e) {
      if (mounted) _toast(context, _failure(e));
    }
  }

  Future<void> _toggleSuspension(AdminUser u) async {
    if (u.suspended) {
      await _act(() => widget.backend.setSuspended(u.id, suspended: false), '정지를 풀었어요.');
      return;
    }
    final reason = await askNote(context, title: '@${u.handle} 정지', action: '정지');
    if (reason == null) return;
    await _act(
      () => widget.backend.setSuspended(u.id, suspended: true, reason: reason),
      '정지했어요. 글을 쓸 수 없고 글이 피드에서 숨겨져요.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final users = _users;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _query,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              labelText: '아이디나 이름으로 찾기',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(tooltip: '찾기', icon: const Icon(Icons.search), onPressed: _search),
            ),
          ),
        ),
        Expanded(
          child: users == null
              ? Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!, style: SgText.small))
              : users.isEmpty
              ? const Center(child: Text('찾는 사람이 없어요.', style: SgText.small))
              : ListView.builder(
                  itemCount: users.length,
                  itemBuilder: (context, i) {
                    final u = users[i];
                    return ListTile(
                      leading: Avatar(
                        initial: u.displayName.isEmpty ? '?' : u.displayName.substring(0, 1),
                        color: avatarPalette[u.id.hashCode.abs() % avatarPalette.length],
                        photoUrl: u.photoUrl,
                      ),
                      title: Text('${u.displayName} @${u.handle}'),
                      subtitle: Text(
                        [
                          '글 ${u.posts}',
                          '30일 차단 ${u.recentBlocks}',
                          if (u.suspended)
                            '정지됨${u.suspendedReason?.isNotEmpty == true ? ' (${u.suspendedReason})' : ''}',
                        ].join(' · '),
                        style: u.suspended ? const TextStyle(color: SgColors.accentText) : null,
                      ),
                      trailing: u.id == widget.myId
                          ? null
                          : PopupMenuButton<String>(
                              tooltip: '관리',
                              onSelected: (v) {
                                if (v == 'suspend') _toggleSuspension(u);
                                if (v == 'photo') _act(() => widget.backend.removePhoto(u.id), '사진을 내렸어요.');
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(value: 'suspend', child: Text(u.suspended ? '정지 풀기' : '정지')),
                                if (u.photoUrl != null) const PopupMenuItem(value: 'photo', child: Text('사진 내리기')),
                              ],
                            ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _StatsTab extends StatefulWidget {
  const _StatsTab({required this.backend});

  final Backend backend;

  @override
  State<_StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<_StatsTab> {
  AdminStats? _stats;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final stats = await widget.backend.adminStats();
      if (mounted) setState(() => (_stats = stats, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = _failure(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    if (s == null) {
      return Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!, style: SgText.small));
    }
    final rows = [
      ('가입한 사람', '${s.users}', '오늘 ${s.usersToday}'),
      ('올라온 글', '${s.posts}', '오늘 ${s.postsToday}'),
      ('검토 대기', '${s.pendingReview}', '필터가 막았거나 판단을 보류한 글'),
      ('정지된 사람', '${s.suspended}', ''),
    ];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final (label, value, note) in rows)
            ListTile(
              title: Text(label),
              subtitle: note.isEmpty ? null : Text(note),
              trailing: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}
