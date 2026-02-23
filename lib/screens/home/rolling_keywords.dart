import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/trend_data.dart';
import '../../theme/app_theme.dart';

/// 한줄 롤링 인기 검색어
class RollingKeywords extends ConsumerStatefulWidget {
  final List<TrendKeyword> keywords;
  final void Function(String keyword)? onTap;
  const RollingKeywords({super.key, required this.keywords, this.onTap});

  @override
  ConsumerState<RollingKeywords> createState() => _RollingKeywordsState();
}

class _RollingKeywordsState extends ConsumerState<RollingKeywords> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _startRolling();
  }

  void _startRolling() {
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _currentIndex =
            (_currentIndex + 1) % widget.keywords.length;
      });
      _startRolling();
    });
  }

  Widget _buildMiniRankChange(TteolgaTheme t, int? rankChange) {
    if (rankChange == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: t.rankUp.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text('NEW',
            style: TextStyle(
                color: t.rankUp,
                fontSize: 9,
                fontWeight: FontWeight.w700)),
      );
    }
    if (rankChange == 0) return const SizedBox.shrink();
    final isUp = rankChange > 0;
    final color = isUp ? t.rankUp : t.rankDown;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(isUp ? Icons.arrow_drop_up : Icons.arrow_drop_down,
            color: color, size: 16),
        Text('${rankChange.abs()}',
            style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.keywords.isEmpty) return const SizedBox();
    final kw = widget.keywords[_currentIndex];
    final t = ref.watch(tteolgaThemeProvider);

    return GestureDetector(
      onTap: () => widget.onTap?.call(kw.keyword),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.5),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: SizedBox(
          key: ValueKey(_currentIndex),
          height: 20,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  '${_currentIndex + 1}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: t.textTertiary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  kw.keyword,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 13,
                    height: 1.2,
                  ),
                ),
              ),
              _buildMiniRankChange(t, kw.rankChange),
            ],
          ),
        ),
      ),
    );
  }
}
