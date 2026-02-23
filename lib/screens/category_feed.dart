import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../models/product.dart';
import '../services/analytics_service.dart';
import '../theme/app_theme.dart';
import '../providers/product_list_provider.dart';
import '../widgets/product_card.dart';
import '../widgets/coupang_banner.dart';
import '../constants/app_constants.dart';
import '../widgets/pinned_chip_header.dart';
import '../widgets/skeleton.dart';

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
      ref
          .read(categoryProductsProvider(_filter).notifier)
          .fetchNextPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tteolgaThemeProvider);
    final state = ref.watch(categoryProductsProvider(_filter));
    final items = state.products;
    final subs = subCategories[widget.category] ?? [];

    return Stack(
      children: [
        RefreshIndicator(
          color: t.textPrimary,
          backgroundColor: t.card,
          onRefresh: () async {
            await ref
                .read(categoryProductsProvider(_filter).notifier)
                .refresh();
          },
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            slivers: [
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
              if (items.isEmpty && state.isLoading)
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
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
                if (state.isLoading && state.hasMore)
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
