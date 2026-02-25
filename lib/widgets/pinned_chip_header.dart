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

  /// 칩별 패딩을 커스텀 (심볼 있는 칩은 좌측 패딩 줄이기 등)
  final EdgeInsets Function(int index, bool selected)? chipPaddingBuilder;

  /// 칩 리스트 오른쪽 끝에 고정 배치할 위젯 (예: 정렬 버튼)
  final Widget? trailingWidget;

  const PinnedChipHeaderDelegate({
    required this.itemCount,
    required this.selectedIndex,
    required this.onSelected,
    required this.theme,
    required this.chipContentBuilder,
    this.chipPaddingBuilder,
    this.trailingWidget,
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
        child: Row(
          children: [
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.fromLTRB(16, 10, trailingWidget != null ? 8 : 16, 10),
                itemCount: itemCount,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, i) {
                  final selected = i == selectedIndex;
                  final padding = chipPaddingBuilder?.call(i, selected)
                      ?? const EdgeInsets.symmetric(horizontal: 16);
                  return GestureDetector(
                    onTap: () => onSelected(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      alignment: Alignment.center,
                      padding: padding,
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
            if (trailingWidget != null)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: trailingWidget!,
              ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant PinnedChipHeaderDelegate oldDelegate) =>
      selectedIndex != oldDelegate.selectedIndex ||
      itemCount != oldDelegate.itemCount ||
      theme != oldDelegate.theme ||
      trailingWidget != oldDelegate.trailingWidget;
}
