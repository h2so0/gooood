import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../models/product.dart';
import '../theme/app_theme.dart';
import '../providers/category_provider.dart';
import '../widgets/product_card.dart';

/// 카테고리 피드 (pull-to-refresh)
class CategoryFeed extends ConsumerWidget {
  final String category;
  final void Function(Product) onTap;
  const CategoryFeed(
      {super.key, required this.category, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tteolgaThemeProvider);
    final products = ref.watch(categoryDealsProvider(category));

    return products.when(
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Text('상품이 없습니다',
                style: TextStyle(color: t.textTertiary)),
          );
        }
        return RefreshIndicator(
          color: t.textPrimary,
          backgroundColor: t.card,
          onRefresh: () async {
            DealCategoryClassifier.instance.clearCache();
            ref.invalidate(categoryDealsProvider(category));
          },
          child: MasonryGridView.count(
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            itemCount: items.length,
            itemBuilder: (context, i) => ProductGridCard(
              product: items[i],
              onTap: () => onTap(items[i]),
            ),
          ),
        );
      },
      loading: () => Center(
        child: CircularProgressIndicator(color: t.textTertiary),
      ),
      error: (_, __) => Center(
        child: Text('불러오기 실패',
            style: TextStyle(color: t.textTertiary)),
      ),
    );
  }
}
