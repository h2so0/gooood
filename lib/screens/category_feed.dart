import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../models/product.dart';
import '../services/analytics_service.dart';
import '../theme/app_theme.dart';
import '../providers/product_list_provider.dart';
import '../widgets/product_card.dart';
import '../constants/app_constants.dart';
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
                  delegate: _SubCategoryHeaderDelegate(
                    subs: subs,
                    selectedSubCategory: _selectedSubCategory,
                    onSelected: (label) {
                      if (label == _selectedSubCategory) {
                        // 같은 탭 재탭 → 상단으로
                        if (_scrollController.hasClients) {
                          _scrollController.animateTo(0,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut);
                        }
                        return;
                      }
                      setState(() {
                        _selectedSubCategory = label;
                      });
                      if (_scrollController.hasClients) {
                        _scrollController.jumpTo(0);
                      }
                      AnalyticsService.logSubCategoryFilter(
                          widget.category, label);
                    },
                    theme: t,
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
                    childCount: items.length,
                    itemBuilder: (context, i) => ProductGridCard(
                      product: items[i],
                      onTap: () => widget.onTap(items[i]),
                    ),
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

class _SubCategoryHeaderDelegate extends SliverPersistentHeaderDelegate {
  final List<String> subs;
  final String? selectedSubCategory;
  final ValueChanged<String?> onSelected;
  final TteolgaTheme theme;

  const _SubCategoryHeaderDelegate({
    required this.subs,
    required this.selectedSubCategory,
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
          itemCount: subs.length + 1,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (context, i) {
            final isAll = i == 0;
            final label = isAll ? '전체' : subs[i - 1];
            final selected = isAll
                ? selectedSubCategory == null
                : selectedSubCategory == label;

            return GestureDetector(
              onTap: () => onSelected(isAll ? null : label),
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
                          color: t.border.withValues(alpha: 0.5),
                          width: 0.8),
                ),
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? t.bg : t.textSecondary,
                    letterSpacing: -0.2,
                  ),
                  child: Text(label),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _SubCategoryHeaderDelegate oldDelegate) =>
      selectedSubCategory != oldDelegate.selectedSubCategory ||
      subs != oldDelegate.subs;
}
