import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/product.dart';
import 'api_providers.dart';
import 'product_list_provider.dart';

final searchResultsProvider =
    FutureProvider.family<List<Product>, String>((ref, query) async {
  if (query.isEmpty) return [];
  try {
    final api = ref.read(naverApiProvider);
    final queryLower = query.toLowerCase();

    // 1) 로드된 피드 상품 중 매칭
    List<Product> hotMatches = [];
    try {
      final hotState = ref.read(hotProductsProvider);
      hotMatches = hotState.products
          .where((p) => p.title.toLowerCase().contains(queryLower))
          .toList();
    } catch (e) { debugPrint('[SearchProvider] hot match error: $e'); }

    // 2) Naver Shopping API 검색 + Firestore 검색 병렬 실행
    final results = await Future.wait([
      api.searchClean(query: query, display: 40),
      _searchFirestore(query),
    ]);
    final searchResults = results[0];
    final firestoreResults = results[1];

    // 3) 결과 합치기 (중복 제거: hotMatches > firestoreResults > searchResults)
    final seenIds = <String>{};
    final merged = <Product>[];

    for (final p in hotMatches) {
      if (seenIds.add(p.id)) merged.add(p);
    }
    for (final p in firestoreResults) {
      if (seenIds.add(p.id)) merged.add(p);
    }
    for (final p in searchResults) {
      if (seenIds.add(p.id)) merged.add(p);
    }

    return merged;
  } catch (e) {
    debugPrint('[SearchProvider] search error: $e');
    rethrow;
  }
});

/// Firestore searchKeywords 기반 검색 (쿠팡 등 외부 소스 포함)
Future<List<Product>> _searchFirestore(String query) async {
  try {
    final words = query.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return [];

    // searchKeywords array-contains로 첫 번째 키워드 매칭
    final snap = await FirebaseFirestore.instance
        .collection('products')
        .where('searchKeywords', arrayContains: words.first)
        .limit(30)
        .get();

    final products = snap.docs
        .map((doc) => Product.fromJson(doc.data()))
        .where((p) {
          // 다중 키워드일 경우 타이틀에서 추가 필터링
          if (words.length <= 1) return true;
          final titleLower = p.title.toLowerCase();
          return words.every((w) => titleLower.contains(w.toLowerCase()));
        })
        .toList();

    return products;
  } catch (e) {
    debugPrint('[SearchProvider] firestore search error: $e');
    return [];
  }
}
