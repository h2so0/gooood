import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../models/product.dart';
import '../providers/product_list_provider.dart';
import 'product_card.dart';

/// 무한스크롤 감지 리스너 생성
VoidCallback infiniteScrollListener(
    ScrollController sc, VoidCallback fetchNext) {
  return () {
    if (sc.position.pixels >= sc.position.maxScrollExtent - 500) {
      fetchNext();
    }
  };
}

/// 상품 그리드 + 로딩 인디케이터 + 하단 여백을 Sliver 리스트로 반환
List<Widget> productGridSlivers({
  required List<Product> products,
  required ProductListState state,
  required void Function(Product) onTap,
  required Color loadingColor,
}) {
  return [
    SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverMasonryGrid.count(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childCount: products.length,
        itemBuilder: (context, i) {
          return ProductGridCard(
            product: products[i],
            onTap: () => onTap(products[i]),
          );
        },
      ),
    ),
    if (state.isLoading && state.hasMore && products.isNotEmpty)
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(child: CircularProgressIndicator(color: loadingColor)),
        ),
      ),
    const SliverToBoxAdapter(child: SizedBox(height: 40)),
  ];
}
