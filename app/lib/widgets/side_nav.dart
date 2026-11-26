import 'package:material_ui/material_ui.dart';

import '../data/app_state.dart';
import '../theme/tokens.dart';
import 'post_tile.dart' show Avatar;
import 'pressable.dart';
import 'symbol_mark.dart';

/// One place in the menu.
class NavItem {
  const NavItem({required this.icon, required this.activeIcon, required this.label, this.badge = 0});

  final IconData icon;
  final IconData activeIcon;
  final String label;

  /// Unread count shown on the icon; 0 hides it.
  final int badge;
}

/// The menu on the left on tablets and computers: icons only on a tablet,
/// icons and names on a wider screen, with the write button and the
/// reader's own account at the bottom.
class SideNav extends StatelessWidget {
  const SideNav({
    super.key,
    required this.state,
    required this.items,
    required this.selected,
    required this.onSelect,
    required this.onCompose,
    required this.expanded,
  });

  final AppState state;
  final List<NavItem> items;
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onCompose;
  final bool expanded;

  static const railWidth = 88.0;
  static const expandedWidth = 260.0;

  @override
  Widget build(BuildContext context) {
    final me = state.me;
    return SizedBox(
      width: expanded ? expandedWidth : railWidth,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: expanded ? SgSpace.md : SgSpace.sm, vertical: SgSpace.sm),
        child: Column(
          crossAxisAlignment: expanded ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            Tooltip(
              message: '홈',
              child: Pressable(
                onTap: () => onSelect(0),
                pressScale: 0.92,
                borderRadius: BorderRadius.circular(SgRadius.pill),
                child: const SizedBox.square(dimension: 52, child: Center(child: SymbolMark(size: 30))),
              ),
            ),
            const SizedBox(height: SgSpace.xs),
            for (var i = 0; i < items.length; i++)
              _NavButton(item: items[i], active: i == selected, expanded: expanded, onTap: () => onSelect(i)),
            const SizedBox(height: SgSpace.lg),
            _WriteButton(expanded: expanded, onTap: onCompose),
            const Spacer(),
            if (me != null)
              Tooltip(
                message: expanded ? '' : '@${me.handle}',
                child: Pressable(
                  onTap: () => onSelect(items.length - 1),
                  borderRadius: BorderRadius.circular(SgRadius.pill),
                  child: Padding(
                    padding: const EdgeInsets.all(SgSpace.md),
                    child: Row(
                      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
                      children: [
                        Avatar(initial: me.initial, color: me.avatarColor, photoUrl: me.photoUrl),
                        if (expanded) ...[
                          const SizedBox(width: SgSpace.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(me.displayName, style: SgText.name, overflow: TextOverflow.ellipsis),
                                Text('@${me.handle}', style: SgText.small, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.active, required this.expanded, required this.onTap});

  final NavItem item;
  final bool active;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = Badge(
      isLabelVisible: item.badge > 0,
      label: Text(item.badge > 99 ? '99+' : '${item.badge}'),
      backgroundColor: SgColors.accent,
      child: AnimatedSwitcher(
        duration: SgMotion.fast,
        child: Icon(active ? item.activeIcon : item.icon, key: ValueKey(active), size: 27, color: SgColors.ink),
      ),
    );
    return Semantics(
      selected: active,
      button: true,
      label: item.label,
      child: ExcludeSemantics(
        child: Tooltip(
          message: expanded ? '' : item.label,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Pressable(
              onTap: onTap,
              borderRadius: BorderRadius.circular(SgRadius.pill),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: expanded ? SgSpace.md : SgSpace.md, vertical: SgSpace.md),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon,
                    if (expanded) ...[
                      const SizedBox(width: 18),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                          color: SgColors.ink,
                        ),
                      ),
                      const SizedBox(width: SgSpace.sm),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WriteButton extends StatelessWidget {
  const _WriteButton({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final button = expanded
        ? SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: SgColors.accent,
                foregroundColor: SgColors.onAccent,
                textStyle: SgText.label(size: 17),
              ),
              child: const Text('생각 쓰기'),
            ),
          )
        : SizedBox.square(
            dimension: 52,
            child: FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: SgColors.accent,
                foregroundColor: SgColors.onAccent,
                padding: EdgeInsets.zero,
                shape: const CircleBorder(),
              ),
              child: const Icon(SgIcons.write),
            ),
          );
    return Tooltip(message: '생각 쓰기', child: button);
  }
}
