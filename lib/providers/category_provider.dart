import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/category_data.dart';
import '../models/product.dart';
import '../services/naver_shopping_api.dart';
import '../utils/product_classifier.dart';
import 'api_providers.dart';
import 'hot_deals_provider.dart';

/// 오늘끝딜 카테고리 분류 (캐시 + 동시 요청 방지)
class DealCategoryClassifier {
  DealCategoryClassifier._();
  static final instance = DealCategoryClassifier._();

  final _cache = <String, String>{};
  DateTime? _cacheTime;
  Future<Map<String, String>>? _pending;

  void clearCache() {
    _cache.clear();
    _cacheTime = null;
    _pending = null;
  }

  Future<Map<String, String>> classify(NaverShoppingApi api) async {
    if (_cacheTime != null &&
        DateTime.now().difference(_cacheTime!) <
            const Duration(minutes: 30) &&
        _cache.isNotEmpty) {
      return _cache;
    }
    if (_pending != null) return _pending!;
    _pending = _doClassify(api);
    try {
      return await _pending!;
    } finally {
      _pending = null;
    }
  }

  Future<Map<String, String>> _doClassify(NaverShoppingApi api) async {
    final sources = await fetchAllSources(api);
    final allProducts = sources.expand((l) => l).toList();
    final result = <String, String>{};

    for (final p in allProducts) {
      if (p.id.startsWith('promo_')) {
        result[p.id] = '프로모션';
        continue;
      }
      final cat = mapToAppCategory(p.category1, p.category2, p.category3);
      if (cat != null) {
        result[p.id] = cat;
        continue;
      }
      final titleCat = classifyByTitle(p.title);
      if (titleCat != null) {
        result[p.id] = titleCat;
      }
    }

    debugPrint(
        '[Category] 전체 분류: ${result.length}/${allProducts.length} '
        '(딜=${sources[0].length}, 라이브=${sources[1].length}, '
        '프로모=${sources[2].length}, 11st=${sources[3].length}, '
        'gmkt=${sources[4].length}, auction=${sources[5].length})');
    _cache
      ..clear()
      ..addAll(result);
    _cacheTime = DateTime.now();
    return result;
  }
}

final categoryDealsProvider =
    FutureProvider.family<List<Product>, String>((ref, category) async {
  try {
    final api = ref.read(naverApiProvider);

    List<Product> best100;
    if (category == '반려동물') {
      best100 =
          await api.searchClean(query: '반려동물 인기상품', display: 100);
    } else {
      final catId = appCategoryIds[category];
      if (catId == null) return [];
      best100 = await api.fetchBest100(categoryId: catId);
    }

    final dealCategories =
        await DealCategoryClassifier.instance.classify(api);
    final allProducts =
        (await fetchAllSources(api)).expand((l) => l).toList();
    final matchingDeals = allProducts
        .where(
            (p) => dealCategories[p.id] == category && p.dropRate > 0)
        .toList();

    final seen = best100.map((p) => p.id).toSet();
    final merged = [
      ...matchingDeals.where((p) => !seen.contains(p.id)),
      ...best100,
    ];
    merged.shuffle(Random());
    return merged;
  } catch (_) {
    return [];
  }
});
