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
  } catch (_) {}

  final allKeywords = <TrendKeyword>[];
  try {
    final categories = ['50000003', '50000000', '50000002', '50000008'];
    for (final cid in categories) {
      try {
        final popular = await api.fetchPopularKeywords(categoryId: cid);
        for (final p in popular.take(5)) {
          allKeywords.add(TrendKeyword(
            keyword: p.keyword,
            ratio: (10 - p.rank + 1).toDouble(),
          ));
        }
      } catch (_) {}
    }
  } catch (_) {}

  final seen = <String>{};
  return allKeywords.where((t) {
    if (seen.contains(t.keyword)) return false;
    seen.add(t.keyword);
    return true;
  }).toList();
});
