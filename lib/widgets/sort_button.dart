import 'package:flutter/material.dart';
import '../models/sort_option.dart';
import '../theme/app_theme.dart';

/// 칩 헤더 내 trailing용 소형 정렬 버튼
class SortChip extends StatelessWidget {
  final SortOption current;
  final TteolgaTheme theme;
  final ValueChanged<SortOption> onChanged;

  const SortChip({
    super.key,
    required this.current,
    required this.theme,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final isActive = current != SortOption.recommended;

    return GestureDetector(
      onTap: () => showSortSheet(context, t, current, onChanged),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? t.textPrimary.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive
                ? t.textPrimary.withValues(alpha: 0.3)
                : t.border.withValues(alpha: 0.5),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_vert,
                size: 13,
                color: isActive ? t.textPrimary : t.textTertiary),
            const SizedBox(width: 3),
            Text(
              current.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? t.textPrimary : t.textSecondary,
              ),
            ),
            Icon(Icons.keyboard_arrow_down,
                size: 13,
                color: isActive ? t.textPrimary : t.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// 정렬 BottomSheet 공용 함수
void showSortSheet(
  BuildContext context,
  TteolgaTheme t,
  SortOption current,
  ValueChanged<SortOption> onChanged,
) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, MediaQuery.of(ctx).padding.bottom + 20),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('정렬',
              style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          ...SortOption.values.map((opt) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  onChanged(opt);
                  Navigator.of(ctx).pop();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        opt == current
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                        color: opt == current
                            ? t.textPrimary
                            : t.textTertiary,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        opt.label,
                        style: TextStyle(
                          color: opt == current
                              ? t.textPrimary
                              : t.textSecondary,
                          fontSize: 15,
                          fontWeight: opt == current
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              )),
        ],
      ),
    ),
  );
}

/// 정렬 툴바 행 — 칩 헤더가 없는 피드(타임딜 등)에서 사용
class SortToolbar extends StatelessWidget {
  final SortOption current;
  final TteolgaTheme theme;
  final ValueChanged<SortOption> onChanged;

  const SortToolbar({
    super.key,
    required this.current,
    required this.theme,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final isActive = current != SortOption.recommended;

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Spacer(),
          GestureDetector(
            onTap: () => showSortSheet(context, t, current, onChanged),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isActive
                    ? t.textPrimary.withValues(alpha: 0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isActive
                      ? t.textPrimary.withValues(alpha: 0.3)
                      : t.border.withValues(alpha: 0.5),
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.swap_vert,
                      size: 14,
                      color: isActive ? t.textPrimary : t.textTertiary),
                  const SizedBox(width: 4),
                  Text(
                    current.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                      color: isActive ? t.textPrimary : t.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.keyboard_arrow_down,
                      size: 14,
                      color: isActive ? t.textPrimary : t.textTertiary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
