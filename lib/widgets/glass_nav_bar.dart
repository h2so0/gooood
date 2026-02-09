import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';

class GlassNavBar extends ConsumerWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const GlassNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  static const _items = [
    _NavItem(Icons.bolt_outlined, Icons.bolt, '홈'),
    _NavItem(Icons.grid_view_outlined, Icons.grid_view_rounded, '카테고리'),
    _NavItem(Icons.search_outlined, Icons.search, '검색'),
    _NavItem(Icons.notifications_none, Icons.notifications, '알림'),
    _NavItem(Icons.person_outline, Icons.person, 'MY'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tteolgaThemeProvider);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      margin: EdgeInsets.fromLTRB(28, 0, 28, bottomPadding + 16),
      height: 54,
      decoration: BoxDecoration(
        color: t.nav,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: t.navBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 24,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(_items.length, (i) {
          final active = i == currentIndex;
          final item = _items[i];
          return GestureDetector(
            onTap: () => onTap(i),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 50,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    active ? item.activeIcon : item.icon,
                    color: active ? t.textPrimary : t.textTertiary,
                    size: 20,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.label,
                    style: TextStyle(
                      color: active ? t.textPrimary : t.textTertiary,
                      fontSize: 9,
                      fontWeight:
                          active ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem(this.icon, this.activeIcon, this.label);
}
