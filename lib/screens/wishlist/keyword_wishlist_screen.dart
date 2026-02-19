import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/keyword_price_data.dart';
import '../../models/keyword_wishlist.dart';
import '../../providers/keyword_price_provider.dart';
import '../../providers/keyword_wishlist_provider.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/screen_header.dart';
import '../detail/product_detail_screen.dart';
import '../search_screen.dart';
import 'target_price_sheet.dart';

class KeywordWishlistScreen extends ConsumerWidget {
  const KeywordWishlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tteolgaThemeProvider);
    final items = ref.watch(keywordWishlistProvider);
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: t.bg,
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, topPadding + 8, 16, 40),
        children: [
          // 헤더: 뒤로가기 + 제목
          ScreenHeader(theme: t, title: '저장'),
          const SizedBox(height: 20),

          if (items.isEmpty)
            _buildEmpty(t)
          else
            ...items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _WishlistCard(item: item),
                )),
        ],
      ),
    );
  }

  Widget _buildEmpty(TteolgaTheme t) {
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmark_border,
                size: 48, color: t.textTertiary),
            const SizedBox(height: 12),
            Text('검색에서 키워드를 찜해보세요',
                style: TextStyle(color: t.textTertiary, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class _WishlistCard extends ConsumerWidget {
  final KeywordWishItem item;
  const _WishlistCard({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tteolgaThemeProvider);
    final analysisAsync =
        ref.watch(keywordPriceAnalysisProvider(item.keyword));
    final historyAsync =
        ref.watch(keywordPriceHistoryProvider(item.keyword));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(t),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 키워드명 (탭→최저가 상품) + 추이 인디케이터
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _navigateToCheapest(context, analysisAsync),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(item.keyword,
                            style: TextStyle(
                                color: t.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right,
                          size: 16, color: t.textTertiary),
                    ],
                  ),
                ),
              ),
              historyAsync.when(
                data: (history) => _trendIndicator(t, history),
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 실시간 가격 정보 (keywordPriceAnalysis 사용)
          analysisAsync.when(
            data: (snapshot) => _buildPriceInfo(t, snapshot),
            loading: () => _buildLoadingRow(t),
            error: (_, _) => historyAsync.when(
              data: (history) => _buildFallbackInfo(t, history),
              loading: () => _buildLoadingRow(t),
              error: (_, _) => Text('데이터 없음',
                  style: TextStyle(color: t.textTertiary, fontSize: 13)),
            ),
          ),

          // 목표가
          if (item.targetPrice != null) ...[
            const SizedBox(height: 8),
            _targetPriceRow(t, analysisAsync),
          ],

          const SizedBox(height: 12),
          Container(height: 0.5, color: t.border),
          const SizedBox(height: 10),

          // 액션 버튼들 (검색 버튼 제거)
          Row(
            children: [
              _actionButton(t, Icons.bar_chart, '가격분석', () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        SearchScreen(initialQuery: item.keyword),
                  ),
                );
              }),
              const SizedBox(width: 16),
              _actionButton(t, Icons.tune, '목표가', () {
                _showTargetPriceSheet(
                    context, ref, t, analysisAsync);
              }),
              const Spacer(),
              _actionButton(t, Icons.delete_outline, '삭제', () {
                AnalyticsService.logKeywordWishlistRemove(item.keyword);
                ref
                    .read(keywordWishlistProvider.notifier)
                    .remove(item.keyword);
                showAppSnackBar(context, t, '${item.keyword} 삭제됨');
              }, color: t.textTertiary),
            ],
          ),
        ],
      ),
    );
  }

  /// 실시간 분석 데이터로 가격 표시
  Widget _buildPriceInfo(TteolgaTheme t, KeywordPriceSnapshot snapshot) {
    if (snapshot.resultCount == 0) {
      return Text('검색 결과 없음',
          style: TextStyle(color: t.textTertiary, fontSize: 13));
    }

    return Row(
      children: [
        // 최저가 강조
        Text(
          formatPrice(snapshot.minPrice),
          style: TextStyle(
            color: t.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '중간 ${formatPrice(snapshot.medianPrice)}',
          style: TextStyle(color: t.textTertiary, fontSize: 13),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${snapshot.resultCount}개',
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  /// Firestore 히스토리 폴백
  Widget _buildFallbackInfo(
      TteolgaTheme t, List<KeywordPriceSummary> history) {
    if (history.isEmpty) {
      return Text('아직 수집된 데이터가 없습니다',
          style: TextStyle(color: t.textTertiary, fontSize: 13));
    }
    final latest = history.last;
    return Row(
      children: [
        Text(
          formatPrice(latest.minPrice),
          style: TextStyle(
            color: t.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '중간 ${formatPrice(latest.medianPrice)} · ${latest.resultCount}개',
          style: TextStyle(color: t.textTertiary, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildLoadingRow(TteolgaTheme t) {
    return Row(
      children: [
        Container(
          width: 80,
          height: 20,
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 120,
          height: 14,
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }

  Widget _trendIndicator(TteolgaTheme t, List<KeywordPriceSummary> history) {
    if (history.length < 2) return const SizedBox.shrink();

    final latest = history.last;
    final prev = history[history.length - 2];
    if (prev.minPrice == 0) return const SizedBox.shrink();

    final change =
        ((latest.minPrice - prev.minPrice) / prev.minPrice * 100);
    final isDown = change < 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (isDown ? t.drop : t.rankDown).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isDown ? Icons.arrow_downward : Icons.arrow_upward,
            size: 12,
            color: isDown ? t.drop : t.rankDown,
          ),
          const SizedBox(width: 2),
          Text(
            '${change.abs().toStringAsFixed(0)}%',
            style: TextStyle(
              color: isDown ? t.drop : t.rankDown,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _targetPriceRow(
      TteolgaTheme t, AsyncValue<KeywordPriceSnapshot> analysisAsync) {
    final reached = analysisAsync.whenOrNull(data: (snapshot) {
      if (item.targetPrice == null || snapshot.resultCount == 0) return false;
      return snapshot.minPrice <= item.targetPrice!;
    });

    return Row(
      children: [
        Icon(Icons.notifications_outlined, size: 14, color: t.textTertiary),
        const SizedBox(width: 4),
        Text('목표가 ${formatPrice(item.targetPrice!)}',
            style: TextStyle(color: t.textTertiary, fontSize: 12)),
        if (reached == true) ...[
          const SizedBox(width: 6),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: t.drop.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('도달!',
                style: TextStyle(
                    color: t.drop,
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ],
    );
  }

  Widget _actionButton(
      TteolgaTheme t, IconData icon, String label, VoidCallback onTap,
      {Color? color}) {
    final c = color ?? t.textSecondary;
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: c),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: c, fontSize: 12)),
        ],
      ),
    );
  }

  void _navigateToCheapest(
    BuildContext context,
    AsyncValue<KeywordPriceSnapshot> analysisAsync,
  ) {
    final seller = analysisAsync.valueOrNull?.cheapestSeller;
    if (seller == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(product: seller.toProduct()),
      ),
    );
  }

  void _showTargetPriceSheet(
    BuildContext context,
    WidgetRef ref,
    TteolgaTheme t,
    AsyncValue<KeywordPriceSnapshot> analysisAsync,
  ) {
    int? currentMin;
    analysisAsync.whenData((snapshot) {
      if (snapshot.resultCount > 0) currentMin = snapshot.minPrice;
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: TargetPriceSheet(
          keyword: item.keyword,
          currentTargetPrice: item.targetPrice,
          currentMinPrice: currentMin,
        ),
      ),
    );
  }
}
