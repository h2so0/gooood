import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/naver_shopping_api.dart';
import '../services/price_tracker.dart';

final naverApiProvider = Provider<NaverShoppingApi>((ref) {
  final api = NaverShoppingApi();
  ref.onDispose(() => api.dispose());
  return api;
});

final priceTrackerProvider = FutureProvider<PriceTracker>((ref) async {
  final api = ref.read(naverApiProvider);
  final tracker = PriceTracker(api);
  await tracker.init();
  _collectFromPopularKeywords(api, tracker);
  return tracker;
});

/// 인기 검색어로 가격 수집 (비동기, 앱 시작 시 1회)
Future<void> _collectFromPopularKeywords(
    NaverShoppingApi api, PriceTracker tracker) async {
  try {
    final categories = ['50000003', '50000000', '50000008'];
    final keywords = <String>[];

    for (final cid in categories) {
      try {
        final popular = await api.fetchPopularKeywords(categoryId: cid);
        keywords.addAll(popular.take(5).map((p) => p.keyword));
      } catch (_) {}
    }

    if (keywords.isNotEmpty) {
      await tracker.collectPrices(keywords);
    }
  } catch (_) {}
}
