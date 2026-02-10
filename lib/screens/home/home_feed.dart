import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../../models/product.dart';
import '../../models/trend_data.dart';
import '../../theme/app_theme.dart';
import '../../providers/hot_deals_provider.dart';
import '../../providers/trend_provider.dart';
import '../../providers/viewed_products_provider.dart';
import '../../utils/formatters.dart';
import '../../widgets/product_card.dart';
import '../../widgets/product_image.dart';
import '../../widgets/coupang_banner.dart';
import '../search_screen.dart';
import 'rolling_keywords.dart';

/// 홈 피드: 롤링 인기 검색어 + 핫딜 그리드
class HomeFeed extends ConsumerStatefulWidget {
  final void Function(Product) onTap;
  const HomeFeed({super.key, required this.onTap});

  @override
  ConsumerState<HomeFeed> createState() => _HomeFeedState();
}

class _HomeFeedState extends ConsumerState<HomeFeed> {
  bool _trendExpanded = false;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tteolgaThemeProvider);
    final hotProducts = ref.watch(hotProductsProvider);
    final trendKeywords = ref.watch(trendKeywordsProvider);
    final droppedProducts = ref.watch(droppedProductsProvider);

    return RefreshIndicator(
      color: t.textPrimary,
      backgroundColor: t.card,
      onRefresh: () async {
        ref.invalidate(hotProductsProvider);
        ref.invalidate(trendKeywordsProvider);
        ref.invalidate(droppedProductsProvider);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        padding: EdgeInsets.zero,
        children: [
          const SizedBox(height: 6),
          trendKeywords.when(
            data: (keywords) {
              if (keywords.isEmpty) return const SizedBox();
              return _buildTrendBar(t, keywords);
            },
            loading: () => const SizedBox(height: 44),
            error: (_, __) => const SizedBox(),
          ),

          const SizedBox(height: 16),

          droppedProducts.when(
            data: (dropped) {
              if (dropped.isEmpty) return const SizedBox();
              return _buildDroppedSection(t, dropped);
            },
            loading: () => const SizedBox(),
            error: (_, __) => const SizedBox(),
          ),

          const CoupangBanner(),
          const SizedBox(height: 20),

          _sectionTitle(t, '오늘의 핫딜'),
          const SizedBox(height: 8),
          hotProducts.when(
            data: (products) {
              if (products.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text('핫딜 상품을 불러오는 중...',
                      style:
                          TextStyle(color: t.textTertiary, fontSize: 13)),
                );
              }
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: MasonryGridView.count(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  itemCount: products.length,
                  itemBuilder: (context, i) => ProductGridCard(
                    product: products[i],
                    onTap: () => widget.onTap(products[i]),
                  ),
                ),
              );
            },
            loading: () => SizedBox(
              height: 200,
              child: Center(
                  child:
                      CircularProgressIndicator(color: t.textTertiary)),
            ),
            error: (_, __) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('불러오기 실패',
                  style: TextStyle(color: t.textSecondary)),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  void _navigateToSearch(String keyword) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchScreen(initialQuery: keyword),
      ),
    );
  }

  Widget _buildRankChange(TteolgaTheme t, int? rankChange) {
    if (rankChange == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: t.rankUp.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'NEW',
          style: TextStyle(
            color: t.rankUp,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    if (rankChange == 0) {
      return Text('—',
          style: TextStyle(color: t.textTertiary, fontSize: 12));
    }
    final isUp = rankChange > 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isUp ? Icons.arrow_drop_up : Icons.arrow_drop_down,
          color: isUp ? t.rankUp : t.rankDown,
          size: 20,
        ),
        Text(
          '${rankChange.abs()}',
          style: TextStyle(
            color: isUp ? t.rankUp : t.rankDown,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildTrendBar(TteolgaTheme t, List<TrendKeyword> keywords) {
    if (_trendExpanded) {
      final items = keywords.take(10).toList();

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: t.border, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('인기 차트',
                      style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => _trendExpanded = false),
                    child: Icon(Icons.keyboard_arrow_up,
                        color: t.textTertiary, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...items.asMap().entries.map((e) {
                final rank = e.key + 1;
                final kw = e.value;

                return GestureDetector(
                  onTap: () => _navigateToSearch(kw.keyword),
                  child: Container(
                    color: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          child: Text(
                            '$rank',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: rank <= 3
                                  ? t.textPrimary
                                  : t.textTertiary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            kw.keyword,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: t.textPrimary,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildRankChange(t, kw.rankChange),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: () {
          if (keywords.isNotEmpty) {
            _navigateToSearch(keywords.first.keyword);
          }
        },
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: t.border, width: 0.5),
          ),
          child: Row(
            children: [
              Text('인기',
                  style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              Expanded(
                child: RollingKeywords(
                  keywords: keywords,
                  onTap: _navigateToSearch,
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _trendExpanded = true),
                child: Icon(Icons.keyboard_arrow_down,
                    color: t.textTertiary, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDroppedSection(TteolgaTheme t, List<Product> dropped) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(t, '가격 하락'),
        const SizedBox(height: 8),
        SizedBox(
          height: 160,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: dropped.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final p = dropped[i];
              return GestureDetector(
                onTap: () => widget.onTap(p),
                child: Container(
                  width: 130,
                  decoration: BoxDecoration(
                    color: t.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: t.border, width: 0.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(12)),
                        child: SizedBox(
                          height: 90,
                          width: double.infinity,
                          child: ProductImage(
                            imageUrl: p.imageUrl,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: t.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                if (p.dropRate > 0) ...[
                                  Text(
                                    '-${p.dropRate.toStringAsFixed(0)}%',
                                    style: TextStyle(
                                      color: t.drop,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Flexible(
                                  child: Text(
                                    formatPrice(p.currentPrice),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: t.textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _sectionTitle(TteolgaTheme t, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Text(
        title,
        style: TextStyle(
          color: t.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
