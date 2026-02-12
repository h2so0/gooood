import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/product.dart';

final viewedProductsProvider =
    StateNotifierProvider<ViewedProductsNotifier, List<Product>>((ref) {
  return ViewedProductsNotifier();
});

class ViewedProductsNotifier extends StateNotifier<List<Product>> {
  ViewedProductsNotifier() : super([]);

  void add(Product product) {
    state = [
      product,
      ...state.where((p) => p.id != product.id),
    ].take(50).toList();
  }
}
