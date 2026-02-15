import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../models/product.dart';
import '../theme/app_theme.dart';
import '../providers/product_list_provider.dart';
import '../widgets/product_card.dart';

const _subCategories = <String, List<String>>{
  '디지털/가전': ['스마트폰/태블릿', '노트북/PC', 'TV/영상가전', '생활가전', '음향/게임'],
  '패션/의류': ['여성의류', '남성의류', '신발/가방', '시계/주얼리', '언더웨어/잠옷'],
  '생활/건강': ['가구/인테리어', '주방용품', '생활용품', '건강식품/비타민', '반려동물'],
  '식품': ['신선식품', '가공식품', '음료/커피', '건강식품', '간식/베이커리'],
  '뷰티': ['스킨케어', '메이크업', '헤어/바디', '향수', '남성뷰티'],
  '스포츠/레저': ['운동복/신발', '헬스/요가', '아웃도어/캠핑', '골프', '자전거/킥보드'],
  '출산/육아': ['유아동복', '기저귀/물티슈', '분유/이유식', '장난감/완구', '유모차/카시트'],
};

/// 카테고리 피드 (무한스크롤 + pull-to-refresh)
class CategoryFeed extends ConsumerStatefulWidget {
  final String category;
  final void Function(Product) onTap;
  const CategoryFeed(
      {super.key, required this.category, required this.onTap});

  @override
  ConsumerState<CategoryFeed> createState() => _CategoryFeedState();
}

class _CategoryFeedState extends ConsumerState<CategoryFeed> {
  final ScrollController _scrollController = ScrollController();
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
    _scrollController.dispose();
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
    final subs = _subCategories[widget.category] ?? [];

    return RefreshIndicator(
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
            SliverToBoxAdapter(
              child: Container(
                decoration: BoxDecoration(
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    itemCount: subs.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (context, i) {
                      final isAll = i == 0;
                      final label = isAll ? '전체' : subs[i - 1];
                      final selected = isAll
                          ? _selectedSubCategory == null
                          : _selectedSubCategory == label;

                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedSubCategory = isAll ? null : label;
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: selected
                                ? t.textPrimary
                                : t.surface,
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
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
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
              ),
            ),
          if (items.isEmpty && state.isLoading)
            SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: t.textTertiary),
              ),
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
    );
  }
}
