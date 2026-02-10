import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/product.dart';
import 'api_providers.dart';
import 'hot_deals_provider.dart';

final searchResultsProvider =
    FutureProvider.family<List<Product>, String>((ref, query) async {
  if (query.isEmpty) return [];
  try {
    final api = ref.read(naverApiProvider);
    final queryLower = query.toLowerCase();

    List<Product> hotMatches = [];
    try {
      final hotState = ref.read(hotProductsProvider);
      hotState.whenData((products) {
        hotMatches = products
            .where((p) => p.title.toLowerCase().contains(queryLower))
            .toList();
      });
    } catch (_) {}

    final searchResults = await api.searchClean(query: query, display: 40);

    if (hotMatches.isEmpty) return searchResults;

    final hotIds = hotMatches.map((p) => p.id).toSet();
    final filtered =
        searchResults.where((p) => !hotIds.contains(p.id)).toList();
    return [...hotMatches, ...filtered];
  } catch (_) {
    return [];
  }
});
