import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../models/product.dart';
import '../theme/app_theme.dart';
import '../providers/product_list_provider.dart';
import '../widgets/product_card.dart';

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

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
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
          .read(categoryProductsProvider(widget.category).notifier)
          .fetchNextPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tteolgaThemeProvider);
    final state = ref.watch(categoryProductsProvider(widget.category));
    final items = state.products;

    return RefreshIndicator(
      color: t.textPrimary,
      backgroundColor: t.card,
      onRefresh: () async {
        await ref
            .read(categoryProductsProvider(widget.category).notifier)
            .refresh();
      },
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        slivers: [
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
