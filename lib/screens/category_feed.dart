import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../models/product.dart';
import '../models/sort_option.dart';
import '../services/analytics_service.dart';
import '../theme/app_theme.dart';
import '../providers/product_list_provider.dart';
import '../widgets/product_card.dart';
import '../widgets/coupang_banner.dart';
import '../constants/app_constants.dart';
import '../widgets/pinned_chip_header.dart';
import '../widgets/skeleton.dart';
import '../widgets/sort_button.dart';

/// 카테고리 피드 (무한스크롤 + pull-to-refresh)
class CategoryFeed extends ConsumerStatefulWidget {
  final String category;
  final void Function(Product) onTap;
  final ScrollController scrollController;
  const CategoryFeed(
      {super.key, required this.category, required this.onTap, required this.scrollController});

  @override
  ConsumerState<CategoryFeed> createState() => _CategoryFeedState();
}

class _CategoryFeedState extends ConsumerState<CategoryFeed> {
  ScrollController get _scrollController => widget.scrollController;
  String? _selectedSubCategory;
  CategoryFilter get _filter => CategoryFilter(
        category: widget.category,
        subCategory: _selectedSubCategory,
      );

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant CategoryFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.category != widget.category) {
      _selectedSubCategory = null;
    }
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

  void _fetchNextPageCurrent() {
    final sort = ref.read(categorySortProvider(widget.category));
    if (sort == SortOption.dropRate) {
      ref.read(categoryDropRateProvider(widget.category).notifier).fetchNextPage();
      return;
    }
    ref.read(categoryProductsProvider(_filter).notifier).fetchNextPage();
  }

  ProductListState _watchCurrentState(WidgetRef ref, SortOption sort) {
    if (sort == SortOption.dropRate) {
      return ref.watch(categoryDropRateProvider(widget.category));
    }
    return ref.watch(categoryProductsProvider(_filter));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tteolgaThemeProvider);
    final sort = ref.watch(categorySortProvider(widget.category));
    final currentState = _watchCurrentState(ref, sort);
    final subs = subCategories[widget.category] ?? [];

    final items = (sort == SortOption.priceLow ||
            sort == SortOption.priceHigh ||
            sort == SortOption.review)
        ? applySortOption(currentState.products, sort)
        : currentState.products;

    return Stack(
      children: [
        RefreshIndicator(
          color: t.textPrimary,
          backgroundColor: t.card,
          onRefresh: () async {
            final s = ref.read(categorySortProvider(widget.category));
            if (s == SortOption.dropRate) {
              await ref.read(categoryDropRateProvider(widget.category).notifier).refresh();
            } else {
              await ref.read(categoryProductsProvider(_filter).notifier).refresh();
            }
          },
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            slivers: [
              // 서브카테고리 칩
              if (subs.isNotEmpty)
                SliverPersistentHeader(
                  pinned: true,
                  delegate: PinnedChipHeaderDelegate(
                    itemCount: subs.length + 1,
                    selectedIndex: _selectedSubCategory == null
                        ? 0
                        : subs.indexOf(_selectedSubCategory!) + 1,
                    onSelected: (i) {
                      final label = i == 0 ? null : subs[i - 1];
                      if (label == _selectedSubCategory) {
                        if (_scrollController.hasClients) {
                          _scrollController.animateTo(0,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut);
                        }
                        return;
                      }
                      setState(() => _selectedSubCategory = label);
                      if (_scrollController.hasClients) {
                        _scrollController.jumpTo(0);
                      }
                      AnalyticsService.logSubCategoryFilter(
                          widget.category, label);
                    },
                    theme: t,
                    trailingWidget: SortChip(
                      current: sort,
                      theme: t,
                      onChanged: (opt) {
                        ref.read(categorySortProvider(widget.category).notifier).state = opt;
                        AnalyticsService.logSortChanged(widget.category, opt.label);
                        if (_scrollController.hasClients) {
                          _scrollController.jumpTo(0);
                        }
                      },
                    ),
                    chipContentBuilder: (i, selected) {
                      final label = i == 0 ? '전체' : subs[i - 1];
                      return AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                          color: selected ? t.bg : t.textSecondary,
                          letterSpacing: -0.2,
                        ),
                        child: Text(label),
                      );
                    },
                  ),
                ),
              if (subs.isEmpty)
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
                        ref.read(categorySortProvider(widget.category).notifier).state = opt;
                        AnalyticsService.logSortChanged(widget.category, opt.label);
                        if (_scrollController.hasClients) {
                          _scrollController.jumpTo(0);
                        }
                      },
                    ),
                    chipContentBuilder: (_, selected) {
                      return AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: t.bg,
                          letterSpacing: -0.2,
                        ),
                        child: Text('전체'),
                      );
                    },
                  ),
                ),
              if (items.isEmpty && currentState.isLoading)
                SliverFillRemaining(
                  child: SkeletonProductGrid(theme: t),
                )
              else if (items.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Text('상품이 없습니다',
                        style: TextStyle(color: t.textTertiary)),
                  ),
                )
              else ...[
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverMasonryGrid.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childCount: BannerMixer.itemCount(items.length),
                    itemBuilder: (context, i) {
                      if (BannerMixer.isBanner(i)) {
                        return const CoupangBannerCard();
                      }
                      final pi = BannerMixer.productIndex(i);
                      return ProductGridCard(
                        product: items[pi],
                        onTap: () => widget.onTap(items[pi]),
                      );
                    },
                  ),
                ),
                if (currentState.isLoading && currentState.hasMore)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                          child:
                              CircularProgressIndicator(color: t.textTertiary)),
                    ),
                  ),
                const SliverToBoxAdapter(
                  child: SizedBox(height: 40),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
