import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/product.dart';
import '../../models/sort_option.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_theme.dart';
import '../../providers/product_list_provider.dart';
import '../../widgets/feed_helpers.dart';

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
  late final VoidCallback _scrollListener;

  @override
  void initState() {
    super.initState();
    _scrollListener = infiniteScrollListener(
      _scrollController,
      () => ref.read(timeDealProductsProvider.notifier).fetchNextPage(),
    );
    _scrollController.addListener(_scrollListener);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tteolgaThemeProvider);
    final sort = ref.watch(timeDealSortProvider);
    final currentState = ref.watch(timeDealProductsProvider);

    // 서버에서 소스별 골고루 셔플된 timeDealFeedOrder 순으로 가져옴.
    // 만료된 상품은 클라이언트에서 필터링.
    final now = DateTime.now().toIso8601String();
    final active = currentState.products
        .where((p) => p.saleEndDate == null || p.saleEndDate!.compareTo(now) > 0)
        .toList();

    final List<Product> products;
    if (sort == SortOption.priceLow ||
        sort == SortOption.priceHigh ||
        sort == SortOption.review ||
        sort == SortOption.dropRate) {
      products = applySortOption(active, sort);
    } else {
      products = active; // 이미 서버에서 소스별 셔플됨
    }

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
                  onSelected: (_) {
                    if (_scrollController.hasClients) {
                      _scrollController.animateTo(
                        0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                    }
                  },
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
                  ...productGridSlivers(
                    products: products,
                    state: currentState,
                    onTap: widget.onTap,
                    loadingColor: t.textTertiary,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
