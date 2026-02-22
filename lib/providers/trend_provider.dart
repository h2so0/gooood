import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/trend_data.dart';
import 'api_providers.dart';

/// 트렌드 키워드 (검색 화면용)
final trendKeywordsProvider =
    FutureProvider<List<TrendKeyword>>((ref) async {
  final api = ref.read(naverApiProvider);

  try {
    final keywords = await api.fetchKeywordRank();
    if (keywords.isNotEmpty) return keywords;
  } catch (e) { debugPrint('[TrendProvider] keyword rank error: $e'); }

  final allKeywords = <TrendKeyword>[];
  try {
    final categories = ['50000003', '50000000', '50000002', '50000008'];
    final results = await Future.wait(
      categories.map((cid) => api.fetchPopularKeywords(categoryId: cid)
          .then<List<PopularKeyword>>((v) => v)
          .catchError((_) => <PopularKeyword>[])),
    );
    for (final popular in results) {
      for (final p in popular.take(5)) {
        allKeywords.add(TrendKeyword(
          keyword: p.keyword,
          ratio: (10 - p.rank + 1).toDouble(),
        ));
      }
    }
  } catch (e) { debugPrint('[TrendProvider] fallback error: $e'); }

  final seen = <String>{};
  return allKeywords.where((t) {
    if (seen.contains(t.keyword)) return false;
    seen.add(t.keyword);
    return true;
  }).toList();
});
