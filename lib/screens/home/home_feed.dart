import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../../models/product.dart';
import '../../theme/app_theme.dart';
import '../../providers/product_list_provider.dart';
import '../../providers/trend_provider.dart';
import '../../widgets/product_card.dart';
import '../../widgets/coupang_banner.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/pinned_chip_header.dart';

/// 홈 피드: 롤링 인기 검색어 + 핫딜 그리드
class HomeFeed extends ConsumerStatefulWidget {
  final void Function(Product) onTap;
  final ScrollController scrollController;
  const HomeFeed({super.key, required this.onTap, required this.scrollController});

  @override
  ConsumerState<HomeFeed> createState() => _HomeFeedState();
}

class _HomeFeedState extends ConsumerState<HomeFeed> {
  int _selectedSourceIndex = 0;
  ScrollController get _scrollController => widget.scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
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
    final products = currentState.products;

    final isInitialLoading = products.isEmpty && currentState.isLoading;

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
                delegate: PinnedChipHeaderDelegate(
                  itemCount: sourceFilterTabs.length,
                  selectedIndex: _selectedSourceIndex,
                  onSelected: (i) {
                    if (i == _selectedSourceIndex) {
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
                  chipPaddingBuilder: (i, _) {
                    final tab = sourceFilterTabs[i];
                    final hasSymbol = tab.symbol != null && tab.colorValue != null;
                    return EdgeInsets.only(
                      left: hasSymbol ? 2 : 16,
                      right: hasSymbol ? 10 : 16,
                    );
                  },
                  chipContentBuilder: (i, selected) {
                    final tab = sourceFilterTabs[i];
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (tab.symbol != null && tab.colorValue != null) ...[
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(tab.colorValue!),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              tab.symbol!,
                              style: TextStyle(
                                fontSize: tab.symbol!.length > 1 ? 10 : 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                height: 1,
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),
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
                    );
                  },
                ),
              ),
              if (isInitialLoading)
                const SliverToBoxAdapter(child: SkeletonHomeFeed())
              else ...[
                const SliverToBoxAdapter(child: SizedBox(height: 6)),
                if (products.isEmpty)
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
                      childCount: BannerMixer.itemCount(products.length),
                      itemBuilder: (context, i) {
                        if (BannerMixer.isBanner(i)) {
                          return const CoupangBannerCard();
                        }
                        final pi = BannerMixer.productIndex(i);
                        return ProductGridCard(
                          product: products[pi],
                          onTap: () => widget.onTap(products[pi]),
                        );
                      },
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
            ],
          ),
        ),
      ],
    );
  }
}
