import 'dart:math' show sin, pi;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/keyword_price_data.dart';
import '../models/product.dart';
import '../providers/keyword_price_provider.dart';
import '../providers/keyword_wishlist_provider.dart';
import '../services/analytics_service.dart';
import '../theme/app_theme.dart';
import '../screens/detail/product_detail_screen.dart';
import '../screens/search_screen.dart';
import '../utils/formatters.dart';
import 'charts/price_trend_chart.dart';

class KeywordPriceSection extends ConsumerWidget {
  final String keyword;
  final bool showWishlistButton;
  final Product? originalProduct;

  const KeywordPriceSection({
    super.key,
    required this.keyword,
    this.showWishlistButton = true,
    this.originalProduct,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tteolgaThemeProvider);
    final analysis = originalProduct != null
        ? ref.watch(keywordPriceAnalysisWithProductProvider(
            (keyword: keyword, product: originalProduct!)))
        : ref.watch(keywordPriceAnalysisProvider(keyword));
    final history = ref.watch(keywordPriceHistoryProvider(keyword));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더: 키워드명 + 찜 버튼
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SearchScreen(initialQuery: keyword),
                    ),
                  ),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          keyword,
                          style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.search, size: 14, color: t.textTertiary),
                    ],
                  ),
                ),
              ),
              if (showWishlistButton) _WishlistButton(keyword: keyword),
            ],
          ),
          const SizedBox(height: 16),

          // 실시간 분석 결과
          analysis.when(
            data: (snapshot) =>
                _buildAnalysis(context, t, snapshot, history),
            loading: () => _buildShimmerSkeleton(t),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text('가격 분석 실패',
                    style: TextStyle(color: t.textTertiary, fontSize: 13)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysis(
    BuildContext context,
    TteolgaTheme t,
    KeywordPriceSnapshot snapshot,
    AsyncValue<List<KeywordPriceSummary>> history,
  ) {
    if (snapshot.resultCount == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text('검색 결과가 없습니다',
              style: TextStyle(color: t.textTertiary, fontSize: 13)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 최저가 탭 카드 + 통계
        _buildStatGrid(context, t, snapshot),
        const SizedBox(height: 20),

        // 가격 범위 바
        _buildPriceRangeBar(t, snapshot),

        // 라인차트 (히스토리가 있을 때만)
        history.when(
          data: (list) {
            if (list.length < 2) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 24),
              child: PriceTrendChart(history: list, theme: t),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
        ),
      ],
    );
  }

  /// 3칸 그리드: 최저가(탭 가능) / 중간가 / 상품수
  Widget _buildStatGrid(
      BuildContext context, TteolgaTheme t, KeywordPriceSnapshot snapshot) {
    return Row(
      children: [
        // 최저가 — 탭하면 최저가 상품으로 이동
        Expanded(
          child: GestureDetector(
            onTap: () => _navigateToCheapest(context, snapshot),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: t.textTertiary.withValues(alpha: 0.2), width: 0.5),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('최저가',
                          style: TextStyle(
                              color: t.textTertiary,
                              fontSize: 11,
                              fontWeight: FontWeight.w500)),
                      const SizedBox(width: 2),
                      Icon(Icons.chevron_right,
                          size: 12, color: t.textTertiary),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      formatPrice(snapshot.minPrice),
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: _statCard(t, '중간가', formatPrice(snapshot.medianPrice))),
        const SizedBox(width: 8),
        Expanded(child: _statCard(t, '상품수', '${snapshot.resultCount}개')),
      ],
    );
  }

  Widget _statCard(TteolgaTheme t, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  color: t.textTertiary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToCheapest(
      BuildContext context, KeywordPriceSnapshot snapshot) {
    final seller = snapshot.cheapestSeller;
    if (seller == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(product: seller.toProduct()),
      ),
    );
  }

  /// 가격 범위 바
  Widget _buildPriceRangeBar(TteolgaTheme t, KeywordPriceSnapshot snapshot) {
    final min = snapshot.minPrice.toDouble();
    final max = snapshot.maxPrice.toDouble();
    final median = snapshot.medianPrice.toDouble();

    final range = max - min;
    final medianRatio =
        range > 0 ? ((median - min) / range).clamp(0.0, 1.0) : 0.5;

    return Column(
      children: [
        SizedBox(
          height: 24,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final barWidth = constraints.maxWidth;
              final dotPosition = medianRatio * barWidth;

              return Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: [
                  // 배경 트랙
                  Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: t.border.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  // 활성 범위
                  Container(
                    height: 6,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          t.textSecondary.withValues(alpha: 0.5),
                          t.textSecondary.withValues(alpha: 0.15),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  // 중간가 dot
                  Positioned(
                    left: (dotPosition - 5).clamp(0.0, barWidth - 10),
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: t.textPrimary,
                        shape: BoxShape.circle,
                        border: Border.all(color: t.card, width: 2),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(formatPrice(snapshot.minPrice),
                style: TextStyle(color: t.textTertiary, fontSize: 11)),
            const Spacer(),
            Text('중간 ${formatPrice(snapshot.medianPrice)}',
                style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(formatPrice(snapshot.maxPrice),
                style: TextStyle(color: t.textTertiary, fontSize: 11)),
          ],
        ),
      ],
    );
  }

  Widget _buildShimmerSkeleton(TteolgaTheme t) {
    return _ShimmerGroup(
      theme: t,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(3, (i) {
              return Expanded(
                child: Container(
                  height: 56,
                  margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 20),
          Container(
            height: 6,
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShimmerGroup extends StatefulWidget {
  final TteolgaTheme theme;
  final Widget child;
  const _ShimmerGroup({required this.theme, required this.child});

  @override
  State<_ShimmerGroup> createState() => _ShimmerGroupState();
}

class _ShimmerGroupState extends State<_ShimmerGroup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final pulse = 0.4 + 0.3 * (1 + sin(_controller.value * 2 * pi));
        return Opacity(opacity: pulse, child: child);
      },
      child: widget.child,
    );
  }
}

class _WishlistButton extends ConsumerWidget {
  final String keyword;
  const _WishlistButton({required this.keyword});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWishlisted = ref.watch(isKeywordWishlistedProvider(keyword));
    final t = ref.watch(tteolgaThemeProvider);

    return GestureDetector(
      onTap: () {
        if (isWishlisted) {
          AnalyticsService.logKeywordWishlistRemove(keyword);
          ref.read(keywordWishlistProvider.notifier).remove(keyword);
        } else {
          AnalyticsService.logKeywordWishlistAdd(keyword);
          ref.read(keywordWishlistProvider.notifier).add(keyword);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(6),
        child: Icon(
          isWishlisted ? Icons.bookmark : Icons.bookmark_border,
          color: isWishlisted ? t.star : t.textTertiary,
          size: 22,
        ),
      ),
    );
  }
}
