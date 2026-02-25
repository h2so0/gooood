import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../../models/product.dart';
import '../../models/sort_option.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_theme.dart';
import '../../providers/product_list_provider.dart';
import '../../widgets/product_card.dart';
import '../../widgets/coupang_banner.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/sort_button.dart';
import '../../widgets/pinned_chip_header.dart';

/// 타임딜 피드: 마감 임박 특가 상품 모음
class TimeDealFeed extends ConsumerStatefulWidget {
  final void Function(Product) onTap;
  final ScrollController scrollController;
  const TimeDealFeed(
      {super.key, required this.onTap, required this.scrollController});

  @override
  ConsumerState<TimeDealFeed> createState() => _TimeDealFeedState();
}

class _TimeDealFeedState extends ConsumerState<TimeDealFeed> {
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
      ref.read(timeDealProductsProvider.notifier).fetchNextPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tteolgaThemeProvider);
    final sort = ref.watch(timeDealSortProvider);
    final currentState = ref.watch(timeDealProductsProvider);

    // 타임딜은 기본이 마감임박순. 클라이언트 정렬만 적용.
    final products = (sort == SortOption.priceLow ||
            sort == SortOption.priceHigh ||
            sort == SortOption.review ||
            sort == SortOption.dropRate)
        ? applySortOption(currentState.products, sort)
        : currentState.products;

    final isInitialLoading = products.isEmpty && currentState.isLoading;

    return Stack(
      children: [
        RefreshIndicator(
          color: t.textPrimary,
          backgroundColor: t.card,
          onRefresh: () async {
            await ref.read(timeDealProductsProvider.notifier).refresh();
          },
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            slivers: [
              // 후킹 카피 + 정렬 (다른 탭 칩 헤더와 동일 높이)
              SliverPersistentHeader(
                pinned: true,
                delegate: PinnedChipHeaderDelegate(
                  itemCount: 1,
                  selectedIndex: 0,
                  onSelected: (_) {},
                  theme: t,
                  trailingWidget: SortChip(
                    current: sort,
                    theme: t,
                    onChanged: (opt) {
                      ref.read(timeDealSortProvider.notifier).state = opt;
                      AnalyticsService.logSortChanged('타임딜', opt.label);
                      if (_scrollController.hasClients) {
                        _scrollController.jumpTo(0);
                      }
                    },
                  ),
                  chipContentBuilder: (_, _) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.local_fire_department,
                          size: 13, color: t.bg),
                      const SizedBox(width: 4),
                      Text(
                        '지금 아니면 못사는 특가',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: t.bg,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (isInitialLoading)
                const SliverToBoxAdapter(child: SkeletonHomeFeed())
              else ...[
                if (products.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 40),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.timer_off_outlined,
                                color: t.textTertiary, size: 48),
                            const SizedBox(height: 12),
                            Text('진행 중인 타임딜이 없습니다',
                                style: TextStyle(
                                    color: t.textTertiary, fontSize: 13)),
                          ],
                        ),
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
