import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../api/backend.dart';
import '../core/nav.dart';
import '../data/app_state.dart';
import '../l10n/l10n.dart';
import '../models/post.dart' show avatarPalette;
import '../theme/tokens.dart';
import '../widgets/post_actions.dart';
import '../widgets/post_tile.dart' show Avatar;
import 'profile_screen.dart';

/// Finds people by handle or name, and thoughts close in meaning to what was
/// typed, not only ones with the same words.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.state});

  final AppState state;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final _controller = TextEditingController(text: widget.state.searchQuery);
  Timer? _debounce;
  bool _searching = false;
  bool _failed = false;

  AppState get state => widget.state;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _changed(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _run(q));
  }

  Future<void> _run(String q) async {
    setState(() {
      _searching = q.trim().isNotEmpty;
      _failed = false;
    });
    try {
      await state.search(q);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(SgSpace.lg, SgSpace.sm, SgSpace.lg, SgSpace.sm),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: SgColors.line)),
          ),
          child: TextField(
            key: const Key('search-input'),
            controller: _controller,
            textInputAction: TextInputAction.search,
            onChanged: _changed,
            onSubmitted: (q) {
              _debounce?.cancel();
              _run(q);
            },
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(SgIcons.search),
              hintText: t('사람이나 생각을 찾아보세요'),
              filled: true,
              fillColor: SgColors.band,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SgRadius.pill),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: ListenableBuilder(listenable: state, builder: (context, _) => _results(context)),
        ),
      ],
    );
  }

  Widget _results(BuildContext context) {
    if (_searching && state.people.isEmpty && state.found.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    Widget note(String text) => Padding(
      padding: const EdgeInsets.only(top: 120),
      child: Text(text, textAlign: TextAlign.center, style: SgText.small),
    );
    if (_failed) {
      return ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [note(t('검색하지 못했어요. 잠시 후 다시 시도해주세요.'))],
      );
    }
    if (state.searchQuery.isEmpty) {
      return ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [note(t('닉네임이나 @아이디로 사람을, 문장으로 비슷한 생각을 찾아요.'))],
      );
    }
    if (state.people.isEmpty && state.found.isEmpty) {
      return ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [note(t('찾는 결과가 없어요.'))],
      );
    }
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        if (state.people.isNotEmpty) ...[
          _Section(t('사람')),
          for (final p in state.people) _PersonTile(state: state, person: p),
        ],
        if (state.found.isNotEmpty) ...[
          _Section(t('비슷한 생각')),
          for (final post in state.found) ConnectedPostTile(state: state, post: post),
        ],
        const SizedBox(height: 96),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(SgSpace.lg, SgSpace.lg, SgSpace.lg, SgSpace.xs),
    child: Semantics(header: true, child: Text(text, style: SgText.meta)),
  );
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({required this.state, required this.person});

  final AppState state;
  final PersonHit person;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Avatar(
      initial: person.displayName.isEmpty ? '?' : person.displayName.substring(0, 1),
      color: avatarPalette[person.id.hashCode.abs() % avatarPalette.length],
      photoUrl: person.photoUrl,
    ),
    title: Text(person.displayName, style: SgText.name),
    subtitle: Text(
      person.bio.isEmpty ? '@${person.handle}' : '@${person.handle} · ${person.bio}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    onTap: () => pushPage<void>(context, (_) => ProfilePage(state: state, userId: person.id)),
  );
}
