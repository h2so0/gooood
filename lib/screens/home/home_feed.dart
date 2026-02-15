import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../../models/product.dart';
import '../../models/trend_data.dart';
import '../../theme/app_theme.dart';
import '../../providers/product_list_provider.dart';
import '../../providers/trend_provider.dart';
import '../../widgets/product_card.dart';
import '../../widgets/coupang_banner.dart';
import '../../widgets/skeleton.dart';
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
  int _trendPage = 0;
  final ScrollController _scrollController = ScrollController();
  final PageController _trendPageController = PageController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _trendPageController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 500) {
      ref.read(hotProductsProvider.notifier).fetchNextPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tteolgaThemeProvider);
    final hotState = ref.watch(hotProductsProvider);
    final trendKeywords = ref.watch(trendKeywordsProvider);
    final products = hotState.products;

    // 초기 로딩: 전체 스켈레톤 표시
    if (products.isEmpty && hotState.isLoading) {
      return const SkeletonHomeFeed();
    }

    return RefreshIndicator(
      color: t.textPrimary,
      backgroundColor: t.card,
      onRefresh: () async {
        await ref.read(hotProductsProvider.notifier).refresh();
        ref.invalidate(trendKeywordsProvider);
      },
      child: ListView(
        controller: _scrollController,
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
            error: (_, _) => const SizedBox(),
          ),

          const SizedBox(height: 16),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: CoupangBanner(),
          ),
          const SizedBox(height: 20),

          _sectionTitle(t, '오늘의 핫딜'),
          const SizedBox(height: 8),
          if (products.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('핫딜 상품을 불러오는 중...',
                  style:
                      TextStyle(color: t.textTertiary, fontSize: 13)),
            )
          else
            Padding(
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
            ),
          if (hotState.isLoading && hotState.hasMore && products.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                  child:
                      CircularProgressIndicator(color: t.textTertiary)),
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

  Widget _buildTrendPage(TteolgaTheme t, List<TrendKeyword> keywords, int offset) {
    final items = keywords.skip(offset).take(10).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: items.asMap().entries.map((e) {
        final rank = offset + e.key + 1;
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
                      color: rank <= 3 ? t.textPrimary : t.textTertiary,
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
                    style: TextStyle(color: t.textPrimary, fontSize: 14),
                  ),
                ),
                const SizedBox(width: 8),
                _buildRankChange(t, kw.rankChange),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTrendBar(TteolgaTheme t, List<TrendKeyword> keywords) {
    if (_trendExpanded) {
      final pageCount = keywords.length > 10 ? 2 : 1;
      const pageHeight = 368.0;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: t.border, width: 0.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                    onTap: () => setState(() {
                      _trendExpanded = false;
                      _trendPage = 0;
                    }),
                    child: Icon(Icons.keyboard_arrow_up,
                        color: t.textTertiary, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: pageHeight,
                child: PageView.builder(
                  controller: _trendPageController,
                  itemCount: pageCount,
                  onPageChanged: (i) => setState(() => _trendPage = i),
                  itemBuilder: (_, i) =>
                      _buildTrendPage(t, keywords, i * 10),
                ),
              ),
              if (pageCount > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(pageCount, (i) {
                      return Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == _trendPage
                              ? t.textPrimary
                              : t.textTertiary.withValues(alpha: 0.3),
                        ),
                      );
                    }),
                  ),
                ),
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
