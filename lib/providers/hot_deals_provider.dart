import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/product.dart';
import '../services/naver_shopping_api.dart';
import '../utils/product_classifier.dart';
import 'api_providers.dart';
import 'category_provider.dart';

/// 6개 소스 병렬 fetch
Future<List<List<Product>>> fetchAllSources(NaverShoppingApi api) {
  return Future.wait([
    api.fetchTodayDeals().catchError((_) => <Product>[]),
    api.fetchShoppingLive().catchError((_) => <Product>[]),
    api.fetchNaverPromotions().catchError((_) => <Product>[]),
    api.fetch11stDeals().catchError((_) => <Product>[]),
    api.fetchGmarketDeals().catchError((_) => <Product>[]),
    api.fetchAuctionDeals().catchError((_) => <Product>[]),
  ]);
}

/// 오늘끝딜 + BEST100 병렬 호출하여 병합
/// [sourcesCallback]이 전달되면 가져온 소스 데이터를 전달 (classify 재사용용)
Future<List<Product>> fetchAllDeals(
  NaverShoppingApi api, {
  void Function(List<Product> allSourceProducts)? sourcesCallback,
}) async {
  final sourcesF = fetchAllSources(api);
  final bestResults = await Future.wait([
    api.fetchBest100(sortType: 'PRODUCT_CLICK').catchError((_) => <Product>[]),
    api.fetchBest100(sortType: 'PRODUCT_BUY').catchError((_) => <Product>[]),
  ]);
  final sources = await sourcesF;

  // 소스 데이터를 콜백으로 전달 (classify에서 재사용)
  final sourceProducts = sources.expand((l) => l).toList();
  sourcesCallback?.call(sourceProducts);

  debugPrint(
      '[HotDeal] 오늘끝딜=${sources[0].length}, 라이브=${sources[1].length}, '
      '프로모=${sources[2].length}, 11번가=${sources[3].length}, '
      'G마켓=${sources[4].length}, 옥션=${sources[5].length}, '
      '클릭BEST=${bestResults[0].length}, 구매BEST=${bestResults[1].length}');

  final all = <Product>[
    for (final list in sources) ...list,
    ...bestResults[0],
    ...bestResults[1],
  ];

  final seen = <String>{};
  final unique = all.where((p) {
    if (seen.contains(p.id)) return false;
    final rawId = extractRawId(p.id);
    if (rawId != null && seen.contains(rawId)) return false;
    seen.add(p.id);
    if (rawId != null) seen.add(rawId);
    return true;
  }).toList();

  unique.shuffle(Random());
  return unique;
}

final hotProductsProvider = FutureProvider<List<Product>>((ref) async {
  try {
    final api = ref.read(naverApiProvider);
    List<Product>? sourceProducts;
    final deals = await fetchAllDeals(
      api,
      sourcesCallback: (products) => sourceProducts = products,
    );
    final filtered = deals
        .where((p) => p.dropRate > 0 || p.id.startsWith('best_'))
        .toList();
    final bestCount =
        filtered.where((p) => p.id.startsWith('best_')).length;
    debugPrint(
        '[HotDeal] 필터 후: total=${filtered.length}, best=$bestCount');
    // 이미 가져온 소스 데이터로 분류 (중복 네트워크 요청 방지)
    if (sourceProducts != null) {
      DealCategoryClassifier.instance.classifyFromProducts(sourceProducts!);
    }
    return filtered;
  } catch (e) {
    debugPrint('[HotDeal] ERROR: $e');
    return [];
  }
});
