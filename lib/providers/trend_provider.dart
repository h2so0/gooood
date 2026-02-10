import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/trend_data.dart';
import 'api_providers.dart';

/// 전체 카테고리 인기 검색어
final popularKeywordsProvider =
    FutureProvider<List<PopularKeyword>>((ref) async {
  try {
    final api = ref.read(naverApiProvider);
    return await api.fetchAllPopularKeywords();
  } catch (_) {
    return [];
  }
});

/// 특정 카테고리 인기 검색어
final categoryPopularProvider =
    FutureProvider.family<List<PopularKeyword>, String>(
        (ref, categoryId) async {
  try {
    final api = ref.read(naverApiProvider);
    return await api.fetchPopularKeywords(categoryId: categoryId);
  } catch (_) {
    return [];
  }
});

/// 인기 검색어 상위 10개의 주간 추이 차트
final trendChartProvider =
    FutureProvider<Map<String, List<TrendChartPoint>>>((ref) async {
  try {
    final api = ref.read(naverApiProvider);

    List<String> topKeywords;
    try {
      final popular = await api.fetchPopularKeywords(
        categoryId: '50000003',
        categoryName: '디지털/가전',
      );
      topKeywords = popular.take(10).map((p) => p.keyword).toList();
    } catch (_) {
      topKeywords = ['냉장고', '노트북', '에어프라이어', '가습기', '블루투스스피커'];
    }

    if (topKeywords.isEmpty) return {};

    final now = DateTime.now();
    final startDate = now
        .subtract(const Duration(days: 28))
        .toIso8601String()
        .split('T')[0];
    final endDate = now.toIso8601String().split('T')[0];

    final chartData = <String, List<TrendChartPoint>>{};

    final futures = <Future<Map<String, List<TrendChartPoint>>>>[];
    for (int i = 0; i < topKeywords.length; i += 5) {
      final batch = topKeywords.skip(i).take(5).toList();
      final groups =
          batch.map((k) => {'groupName': k, 'keywords': [k]}).toList();
      futures.add(api
          .fetchTrendChart(
            keywordGroups: groups,
            startDate: startDate,
            endDate: endDate,
          )
          .catchError((_) => <String, List<TrendChartPoint>>{}));
    }

    final results = await Future.wait(futures);
    for (final r in results) {
      chartData.addAll(r);
    }

    return chartData;
  } catch (_) {
    return {};
  }
});

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

  if (allKeywords.isNotEmpty) {
    final seen = <String>{};
    return allKeywords.where((t) {
      if (seen.contains(t.keyword)) return false;
      seen.add(t.keyword);
      return true;
    }).toList();
  }

  try {
    final deals = await api.fetchTodayDeals();
    for (final d in deals.where((p) => p.dropRate > 0).take(20)) {
      var name = d.title.replaceAll(RegExp(r'\[.*?\]'), '').trim();
      final words = name.split(' ').where((w) => w.length > 1).toList();
      if (words.isNotEmpty) {
        final keyword = words.take(2).join(' ');
        allKeywords.add(TrendKeyword(keyword: keyword, ratio: d.dropRate));
      }
    }
  } catch (_) {}

  final seen = <String>{};
  return allKeywords.where((t) {
    if (seen.contains(t.keyword)) return false;
    seen.add(t.keyword);
    return true;
  }).toList();
});
