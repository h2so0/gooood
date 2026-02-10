import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/category_data.dart';
import '../models/product.dart';
import '../services/naver_shopping_api.dart';
import '../services/price_tracker.dart';
import '../utils/product_classifier.dart';

// ── API & Tracker ──

final naverApiProvider = Provider<NaverShoppingApi>((ref) {
  final api = NaverShoppingApi();
  ref.onDispose(() => api.dispose());
  return api;
});

final priceTrackerProvider = FutureProvider<PriceTracker>((ref) async {
  final api = ref.read(naverApiProvider);
  final tracker = PriceTracker(api);
  await tracker.init();
  // 인기 검색어 기반으로 가격 수집 (백그라운드)
  _collectFromPopularKeywords(api, tracker);
  return tracker;
});

/// 인기 검색어로 가격 수집 (비동기, 앱 시작 시 1회)
Future<void> _collectFromPopularKeywords(
    NaverShoppingApi api, PriceTracker tracker) async {
  try {
    // 디지털/가전, 패션의류, 생활/건강 상위 키워드로 수집
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

// ── 실시간 인기 검색어 (네이버 쇼핑인사이트 실제 데이터) ──

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
final categoryPopularProvider = FutureProvider.family<List<PopularKeyword>,
    String>((ref, categoryId) async {
  try {
    final api = ref.read(naverApiProvider);
    return await api.fetchPopularKeywords(categoryId: categoryId);
  } catch (_) {
    return [];
  }
});

// ── 검색 트렌드 차트 (DataLab 기반) ──

/// 인기 검색어 상위 10개의 주간 추이 차트
final trendChartProvider =
    FutureProvider<Map<String, List<TrendChartPoint>>>((ref) async {
  try {
    final api = ref.read(naverApiProvider);

    // 디지털/가전 인기 검색어 상위 10개를 차트에 사용
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
    final startDate =
        now.subtract(const Duration(days: 28)).toIso8601String().split('T')[0];
    final endDate = now.toIso8601String().split('T')[0];

    final chartData = <String, List<TrendChartPoint>>{};

    // 5개씩 배치 (병렬)
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

// ── 네이버 쇼핑 실제 핫딜 (오늘끝딜 + 타임딜 + BEST100 병합) ──

/// 6개 소스 (todayDeals, shoppingLive, naverPromotions, 11st, gmarket, auction) 병렬 fetch
Future<List<List<Product>>> _fetchAllSources(NaverShoppingApi api) {
  return Future.wait([
    api.fetchTodayDeals().catchError((_) => <Product>[]),
    api.fetchShoppingLive().catchError((_) => <Product>[]),
    api.fetchNaverPromotions().catchError((_) => <Product>[]),
    api.fetch11stDeals().catchError((_) => <Product>[]),
    api.fetchGmarketDeals().catchError((_) => <Product>[]),
    api.fetchAuctionDeals().catchError((_) => <Product>[]),
  ]);
}

/// 오늘끝딜 + BEST100(클릭순) + BEST100(구매순) 병렬 호출하여 병합
Future<List<Product>> _fetchAllDeals(NaverShoppingApi api) async {
  final sourcesF = _fetchAllSources(api);
  final bestResults = await Future.wait([
    api.fetchBest100(sortType: 'PRODUCT_CLICK').catchError((_) => <Product>[]),
    api.fetchBest100(sortType: 'PRODUCT_BUY').catchError((_) => <Product>[]),
  ]);
  final sources = await sourcesF;

  debugPrint('[HotDeal] 오늘끝딜=${sources[0].length}, 라이브=${sources[1].length}, 프로모=${sources[2].length}, 11번가=${sources[3].length}, G마켓=${sources[4].length}, 옥션=${sources[5].length}, 클릭BEST=${bestResults[0].length}, 구매BEST=${bestResults[1].length}');

  final all = <Product>[
    for (final list in sources) ...list,
    ...bestResults[0],
    ...bestResults[1],
  ];

  // 크로스 소스 중복 제거: 네이버 소스(deal_/best_/live_/promo_)는 같은 productId 공유
  // G마켓/옥션도 같은 itemNo 공유
  final seen = <String>{};
  final unique = all.where((p) {
    if (seen.contains(p.id)) return false;
    // 네이버 소스: prefix 제거한 순수 productId로 중복 체크
    final rawId = extractRawId(p.id);
    if (rawId != null && seen.contains(rawId)) return false;
    seen.add(p.id);
    if (rawId != null) seen.add(rawId);
    return true;
  }).toList();

  // 할인율 높은 순 정렬 후 랜덤 섞기
  // 상위 할인 상품은 앞에 유지하되 같은 구간 내에서 셔플
  unique.sort((a, b) => b.dropRate.compareTo(a.dropRate));
  final rng = Random();
  // 10개씩 구간별로 셔플 → 순서에 변화를 주되 할인율 큰 게 대체로 앞에
  for (int i = 0; i < unique.length; i += 10) {
    final end = (i + 10).clamp(0, unique.length);
    final chunk = unique.sublist(i, end)..shuffle(rng);
    unique.setRange(i, end, chunk);
  }
  return unique;
}

final hotProductsProvider = FutureProvider<List<Product>>((ref) async {
  try {
    final api = ref.read(naverApiProvider);
    final deals = await _fetchAllDeals(api);
    // 오늘끝딜은 할인율 있는 것만, BEST100은 인기상품이므로 전부 표시
    final filtered = deals.where((p) => p.dropRate > 0 || p.id.startsWith('best_')).toList();
    final bestCount = filtered.where((p) => p.id.startsWith('best_')).length;
    debugPrint('[HotDeal] 필터 후: total=${filtered.length}, best=$bestCount');
    // 오늘끝딜 카테고리 분류를 백그라운드로 미리 시작
    _classifyTodayDeals(api);
    return filtered;
  } catch (e) {
    debugPrint('[HotDeal] ERROR: $e');
    return [];
  }
});

// ── 가격 하락 상품 (축적 데이터 기반) ──

final droppedProductsProvider = FutureProvider<List<Product>>((ref) async {
  try {
    final tracker = await ref.watch(priceTrackerProvider.future);
    final dropped = tracker.getDroppedProducts(days: 7);

    return dropped.map((tp) => Product(
      id: tp.id,
      title: tp.title,
      link: tp.link,
      imageUrl: tp.imageUrl,
      currentPrice: tp.currentPrice,
      previousPrice: tp.previousPrice,
      mallName: tp.mallName,
      category1: tp.category1,
    )).toList();
  } catch (_) {
    return [];
  }
});

// ── 검색 결과 ──

final searchResultsProvider =
    FutureProvider.family<List<Product>, String>((ref, query) async {
  if (query.isEmpty) return [];
  try {
    final api = ref.read(naverApiProvider);
    final queryLower = query.toLowerCase();

    // 핫딜 상품 중 키워드 매칭 (이미 로드된 경우)
    List<Product> hotMatches = [];
    try {
      final hotState = ref.read(hotProductsProvider);
      hotState.whenData((products) {
        hotMatches = products
            .where((p) => p.title.toLowerCase().contains(queryLower))
            .toList();
      });
    } catch (_) {}

    // 일반 검색 결과
    final searchResults = await api.searchClean(query: query, display: 40);

    // 핫딜 매칭 상품을 상단에, 나머지 검색결과를 아래에 (중복 제거)
    if (hotMatches.isEmpty) return searchResults;

    final hotIds = hotMatches.map((p) => p.id).toSet();
    final filtered = searchResults.where((p) => !hotIds.contains(p.id)).toList();
    return [...hotMatches, ...filtered];
  } catch (_) {
    return [];
  }
});

// ── 카테고리 (Best100 카테고리별 직접 + 오늘끝딜 분류) ──

/// 오늘끝딜 카테고리 분류 (캐시 + 동시 요청 방지)
final _dealCatCache = <String, String>{};
DateTime? _dealCatCacheTime;
Future<Map<String, String>>? _pendingDealCat;

/// 새로고침 시 캐시 초기화
void clearDealCategoryCache() {
  _dealCatCache.clear();
  _dealCatCacheTime = null;
  _pendingDealCat = null;
}

Future<Map<String, String>> _classifyTodayDeals(NaverShoppingApi api) async {
  if (_dealCatCacheTime != null &&
      DateTime.now().difference(_dealCatCacheTime!) < const Duration(minutes: 30) &&
      _dealCatCache.isNotEmpty) {
    return _dealCatCache;
  }
  if (_pendingDealCat != null) return _pendingDealCat!;
  _pendingDealCat = _doClassifyTodayDeals(api);
  try {
    return await _pendingDealCat!;
  } finally {
    _pendingDealCat = null;
  }
}

Future<Map<String, String>> _doClassifyTodayDeals(NaverShoppingApi api) async {
  // 모든 소스에서 상품을 가져와 카테고리 분류 (Firestore 캐시 → 추가 API 호출 없음)
  final sources = await _fetchAllSources(api);
  final allProducts = sources.expand((l) => l).toList();
  final result = <String, String>{};

  // 로컬 키워드 매칭으로 분류 (API 호출 0회)
  for (final p in allProducts) {
    // 프로모션은 그대로 "프로모션"
    if (p.id.startsWith('promo_')) {
      result[p.id] = '프로모션';
      continue;
    }
    // 1차: 네이버 카테고리 정보가 있으면 활용
    final cat = mapToAppCategory(p.category1, p.category2, p.category3);
    if (cat != null) {
      result[p.id] = cat;
      continue;
    }
    // 2차: 제목 기반 키워드 매칭
    final titleCat = classifyByTitle(p.title);
    if (titleCat != null) {
      result[p.id] = titleCat;
    }
  }

  debugPrint('[Category] 전체 분류: ${result.length}/${allProducts.length} '
      '(딜=${sources[0].length}, 라이브=${sources[1].length}, 프로모=${sources[2].length}, 11st=${sources[3].length}, gmkt=${sources[4].length}, auction=${sources[5].length})');
  _dealCatCache..clear()..addAll(result);
  _dealCatCacheTime = DateTime.now();
  return result;
}

final categoryDealsProvider =
    FutureProvider.family<List<Product>, String>((ref, category) async {
  try {
    final api = ref.read(naverApiProvider);

    // 1. 카테고리별 Best100 (1회 호출)
    List<Product> best100;
    if (category == '반려동물') {
      best100 = await api.searchClean(query: '반려동물 인기상품', display: 100);
    } else {
      final catId = appCategoryIds[category];
      if (catId == null) return [];
      best100 = await api.fetchBest100(categoryId: catId);
    }

    // 2. 전체 소스에서 해당 카테고리 상품 추출 (모두 캐시됨)
    final dealCategories = await _classifyTodayDeals(api);
    final allProducts = (await _fetchAllSources(api)).expand((l) => l).toList();
    final matchingDeals = allProducts
        .where((p) =>
            dealCategories[p.id] == category &&
            p.dropRate > 0)
        .toList();

    // 3. 병합 (매칭 상품 상단, 중복 제거) + 구간 셔플
    final seen = best100.map((p) => p.id).toSet();
    final merged = [
      ...matchingDeals.where((p) => !seen.contains(p.id)),
      ...best100,
    ];
    merged.sort((a, b) => b.dropRate.compareTo(a.dropRate));
    final rng = Random();
    for (int i = 0; i < merged.length; i += 10) {
      final end = (i + 10).clamp(0, merged.length);
      final chunk = merged.sublist(i, end)..shuffle(rng);
      merged.setRange(i, end, chunk);
    }
    return merged;
  } catch (_) {
    return [];
  }
});

// ── 내가 본 상품 기록 ──

final viewedProductsProvider =
    StateNotifierProvider<ViewedProductsNotifier, List<Product>>((ref) {
  return ViewedProductsNotifier();
});

class ViewedProductsNotifier extends StateNotifier<List<Product>> {
  ViewedProductsNotifier() : super([]);

  void add(Product product) {
    // 중복 제거 후 맨 앞에 추가
    state = [
      product,
      ...state.where((p) => p.id != product.id),
    ].take(50).toList();
  }
}

// ── 트렌드 키워드 (검색 화면용 - 실제 인기 검색어) ──

final trendKeywordsProvider =
    FutureProvider<List<TrendKeyword>>((ref) async {
  final api = ref.read(naverApiProvider);

  // 1차: BEST 키워드 랭킹 API (순위 변동 데이터 포함)
  try {
    final keywords = await api.fetchKeywordRank();
    if (keywords.isNotEmpty) return keywords;
  } catch (_) {}

  // 2차: DataLab Shopping Insight 인기 검색어
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

  // 3차: 핫딜 상품명에서 키워드 추출
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

