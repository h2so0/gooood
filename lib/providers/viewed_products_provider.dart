import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/product.dart';
import 'api_providers.dart';

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

final droppedProductsProvider = FutureProvider<List<Product>>((ref) async {
  try {
    final tracker = await ref.watch(priceTrackerProvider.future);
    final dropped = tracker.getDroppedProducts(days: 7);

    return dropped
        .map((tp) => Product(
              id: tp.id,
              title: tp.title,
              link: tp.link,
              imageUrl: tp.imageUrl,
              currentPrice: tp.currentPrice,
              previousPrice: tp.previousPrice,
              mallName: tp.mallName,
              category1: tp.category1,
            ))
        .toList();
  } catch (_) {
    return [];
  }
});
