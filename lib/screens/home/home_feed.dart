import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../../models/product.dart';
import '../../models/trend_data.dart';
import '../../services/analytics_service.dart';
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
  final ScrollController scrollController;
  const HomeFeed({super.key, required this.onTap, required this.scrollController});

  @override
  ConsumerState<HomeFeed> createState() => _HomeFeedState();
}

class _HomeFeedState extends ConsumerState<HomeFeed> {
  bool _trendExpanded = false;
  int _trendPage = 0;
  int _selectedSourceIndex = 0;
  ScrollController get _scrollController => widget.scrollController;
  final PageController _trendPageController = PageController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _trendPageController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 500) {
      _fetchNextPageCurrent();
    }
  }

  ProductListState _watchCurrentState(WidgetRef ref) {
    final tab = sourceFilterTabs[_selectedSourceIndex];
    if (tab.sourceKey == null) {
      return ref.watch(hotProductsProvider);
    }
    return ref.watch(sourceFilteredProductsProvider(tab.sourceKey!));
  }

  Future<void> _refreshCurrent() async {
    final tab = sourceFilterTabs[_selectedSourceIndex];
    if (tab.sourceKey == null) {
      await ref.read(hotProductsProvider.notifier).refresh();
    } else {
      await ref
          .read(sourceFilteredProductsProvider(tab.sourceKey!).notifier)
          .refresh();
    }
  }

  void _fetchNextPageCurrent() {
    final tab = sourceFilterTabs[_selectedSourceIndex];
    if (tab.sourceKey == null) {
      ref.read(hotProductsProvider.notifier).fetchNextPage();
    } else {
      ref
          .read(sourceFilteredProductsProvider(tab.sourceKey!).notifier)
          .fetchNextPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tteolgaThemeProvider);
    final currentState = _watchCurrentState(ref);
    final trendKeywords = ref.watch(trendKeywordsProvider);
    final products = currentState.products;

    // 초기 로딩: 전체 탭일 때만 전체 스켈레톤 표시
    if (products.isEmpty && currentState.isLoading && _selectedSourceIndex == 0) {
      return const SkeletonHomeFeed();
    }

    return Stack(
      children: [
        RefreshIndicator(
          color: t.textPrimary,
          backgroundColor: t.card,
          onRefresh: () async {
            await _refreshCurrent();
            ref.invalidate(trendKeywordsProvider);
          },
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: _SourceFilterHeaderDelegate(
                  tabs: sourceFilterTabs,
                  selectedIndex: _selectedSourceIndex,
                  onSelected: (i) {
                    if (i == _selectedSourceIndex) {
                      // 같은 탭 재탭 → 상단으로
                      if (_scrollController.hasClients) {
                        _scrollController.animateTo(0,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut);
                      }
                      return;
                    }
                    setState(() => _selectedSourceIndex = i);
                    if (_scrollController.hasClients) {
                      _scrollController.jumpTo(0);
                    }
                  },
                  theme: t,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 6)),
              SliverToBoxAdapter(
                child: trendKeywords.when(
                  data: (keywords) {
                    if (keywords.isEmpty) return const SizedBox();
                    return _buildTrendBar(t, keywords);
                  },
                  loading: () => const SizedBox(height: 44),
                  error: (_, _) => const SizedBox(),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: CoupangBanner(),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              if (products.isEmpty && currentState.isLoading)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                        child:
                            CircularProgressIndicator(color: t.textTertiary)),
                  ),
                )
              else if (products.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 40),
                    child: Center(
                      child: Text('상품이 없습니다',
                          style:
                              TextStyle(color: t.textTertiary, fontSize: 13)),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverMasonryGrid.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childCount: products.length,
                    itemBuilder: (context, i) => ProductGridCard(
                      product: products[i],
                      onTap: () => widget.onTap(products[i]),
                    ),
                  ),
                ),
              if (currentState.isLoading &&
                  currentState.hasMore &&
                  products.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                        child:
                            CircularProgressIndicator(color: t.textTertiary)),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
        ),
      ],
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
          onTap: () {
            AnalyticsService.logTrendingKeywordTap(kw.keyword, rank: rank);
            _navigateToSearch(kw.keyword);
          },
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
            AnalyticsService.logTrendingKeywordTap(
                keywords.first.keyword, rank: 1);
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
                  onTap: (keyword) {
                    final idx = keywords.indexWhere((k) => k.keyword == keyword);
                    AnalyticsService.logTrendingKeywordTap(
                        keyword, rank: idx + 1);
                    _navigateToSearch(keyword);
                  },
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

}

class _SourceFilterHeaderDelegate extends SliverPersistentHeaderDelegate {
  final List<SourceTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final TteolgaTheme theme;

  const _SourceFilterHeaderDelegate({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
    required this.theme,
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
          itemCount: tabs.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (context, i) {
            final tab = tabs[i];
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
                          color: t.border.withValues(alpha: 0.5), width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (tab.symbol != null && tab.colorValue != null) ...[
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(tab.colorValue!),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          tab.symbol!,
                          style: TextStyle(
                            fontSize: tab.symbol!.length > 1 ? 9 : 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                        color: selected ? t.bg : t.textSecondary,
                        letterSpacing: -0.2,
                      ),
                      child: Text(tab.label),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _SourceFilterHeaderDelegate oldDelegate) =>
      selectedIndex != oldDelegate.selectedIndex;
}
