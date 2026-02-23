import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 핀 고정 수평 칩 헤더 (홈 소스 필터 / 카테고리 서브 탭 공용)
class PinnedChipHeaderDelegate extends SliverPersistentHeaderDelegate {
  final int itemCount;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final TteolgaTheme theme;

  /// 각 칩의 내용을 빌드. [selected] 여부에 따라 색상 등을 구분.
  final Widget Function(int index, bool selected) chipContentBuilder;

  const PinnedChipHeaderDelegate({
    required this.itemCount,
    required this.selectedIndex,
    required this.onSelected,
    required this.theme,
    required this.chipContentBuilder,
  });

  @override
  double get minExtent => 52;
  @override
  double get maxExtent => 52;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final t = theme;
    return Container(
      decoration: BoxDecoration(
        color: t.bg,
        border: Border(
          bottom: BorderSide(
            color: t.border.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
      ),
      child: SizedBox(
        height: 52,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          itemCount: itemCount,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (context, i) {
            final selected = i == selectedIndex;
            return GestureDetector(
              onTap: () => onSelected(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: selected ? t.textPrimary : t.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: selected
                      ? null
                      : Border.all(
                          color: t.border.withValues(alpha: 0.5),
                          width: 0.8),
                ),
                child: chipContentBuilder(i, selected),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant PinnedChipHeaderDelegate oldDelegate) =>
      selectedIndex != oldDelegate.selectedIndex ||
      itemCount != oldDelegate.itemCount;
}
