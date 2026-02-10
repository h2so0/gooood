import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../constants/app_constants.dart';
import '../models/product.dart';
import '../models/trend_data.dart';
import 'cache/memory_cache.dart';
import 'cache/firestore_cache.dart';
import 'product_filter.dart';
import 'api/deal_fetcher.dart';

export '../models/trend_data.dart';

class NaverShoppingApi {
  static const _clientId = 'hiD1em_BVH7_sHIirwVD';
  static const _clientSecret = 'b6yEA6sv6W';
  static const _shopUrl = 'https://openapi.naver.com/v1/search/shop.json';
  static const _trendUrl = 'https://openapi.naver.com/v1/datalab/search';
  static const _insightUrl =
      'https://datalab.naver.com/shoppingInsight/getKeywordRank.naver';

  /// 네이버 쇼핑 카테고리 코드
  static const shoppingCategories = {
    '디지털/가전': '50000003',
    '패션의류': '50000000',
    '화장품/미용': '50000002',
    '생활/건강': '50000008',
    '식품': '50000006',
    '스포츠/레저': '50000007',
    '출산/육아': '50000005',
    '패션잡화': '50000001',
    '가구/인테리어': '50000004',
  };

  final http.Client _client;
  final MemoryCache _cache = MemoryCache();
  late final DealFetcher _dealFetcher;

  NaverShoppingApi({http.Client? client})
      : _client = client ?? http.Client() {
    _dealFetcher = DealFetcher(client: _client, cache: _cache);
  }

  Map<String, String> get _headers => {
        'X-Naver-Client-Id': _clientId,
        'X-Naver-Client-Secret': _clientSecret,
      };

  // ── 검색 (클라이언트 직접 호출) ──

  Future<List<Product>> search({
    required String query,
    int display = 20,
    int start = 1,
    String sort = 'sim',
  }) async {
    final cacheKey = 'shop|$query|$display|$start|$sort';
    final cached = _cache.get<List<Product>>(cacheKey);
    if (cached != null) return cached;

    final uri = Uri.parse(_shopUrl).replace(queryParameters: {
      'query': query,
      'display': display.toString(),
      'start': start.toString(),
      'sort': sort,
    });

    final response = await _client.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw NaverApiException(
          'API failed: ${response.statusCode}', response.statusCode);
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final items = (json['items'] as List<dynamic>?) ?? [];
    final products = items
        .map((item) => Product.fromNaverApi(item as Map<String, dynamic>))
        .where((p) => p.currentPrice > 0)
        .toList();

    final filtered = prioritizeQuality(filterProducts(products));
    _cache.put(cacheKey, filtered);
    return filtered;
  }

  Future<List<Product>> searchClean({
    required String query,
    int display = 40,
  }) async {
    final raw = await search(query: query, display: display, sort: 'sim');
    return filterParts(raw);
  }

  Future<List<Product>> searchWithPriceCompare({
    required String query,
    int display = 100,
  }) async {
    final raw = await search(query: query, display: display, sort: 'sim');
    final filtered = filterParts(filterProducts(raw));

    final groups = <String, List<Product>>{};
    for (final p in filtered) {
      final key = groupKey(p);
      groups.putIfAbsent(key, () => []).add(p);
    }

    final results = <Product>[];
    for (final group in groups.values) {
      if (group.length < 2) {
        results.add(group.first);
        continue;
      }

      group.sort((a, b) => a.currentPrice.compareTo(b.currentPrice));
      final cheapest = group.first;
      final mostExpensive = group.last;

      final spread =
          (mostExpensive.currentPrice - cheapest.currentPrice) /
              mostExpensive.currentPrice *
              100;

      if (spread >= 5) {
        results.add(cheapest.copyWith(
          previousPrice: mostExpensive.currentPrice,
        ));
      } else {
        results.add(cheapest);
      }
    }

    results.sort((a, b) => b.dropRate.compareTo(a.dropRate));
    return results;
  }

  // ── 트렌드 차트 ──

  Future<Map<String, List<TrendChartPoint>>> fetchTrendChart({
    required List<Map<String, dynamic>> keywordGroups,
    required String startDate,
    required String endDate,
  }) async {
    final cacheKey =
        'chart|$startDate|${keywordGroups.map((g) => g['groupName']).join(",")}';
    final cached = _cache.get<Map<String, List<TrendChartPoint>>>(cacheKey);
    if (cached != null) return cached;

    final response = await _client.post(
      Uri.parse(_trendUrl),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'startDate': startDate,
        'endDate': endDate,
        'timeUnit': 'week',
        'keywordGroups': keywordGroups,
      }),
    );

    if (response.statusCode != 200) {
      throw NaverApiException(
          'Chart API failed: ${response.statusCode}', response.statusCode);
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final apiResults = (json['results'] as List<dynamic>?) ?? [];

    final chartData = <String, List<TrendChartPoint>>{};
    for (final r in apiResults) {
      final name = r['title'] as String;
      final data = (r['data'] as List<dynamic>?) ?? [];
      chartData[name] = data
          .map((d) => TrendChartPoint(
                period: d['period'] as String,
                ratio: (d['ratio'] as num).toDouble(),
              ))
          .toList();
    }

    _cache.put(cacheKey, chartData);
    return chartData;
  }

  // ── 인기 검색어 ──

  Future<List<PopularKeyword>> fetchPopularKeywords({
    required String categoryId,
    String? categoryName,
  }) async {
    final cacheKey = 'popular|$categoryId';
    final cached = _cache.get<List<PopularKeyword>>(cacheKey);
    if (cached != null) return cached;

    final firestore = await firestoreList(
      CacheKeys.popularKeywords(categoryId),
      PopularKeyword.fromJson,
    );
    if (firestore != null) {
      _cache.put(cacheKey, firestore);
      return firestore;
    }

    if (kIsWeb) return [];

    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final response = await _client.post(
      Uri.parse(_insightUrl),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Referer':
            'https://datalab.naver.com/shoppingInsight/sCategory.naver',
        'User-Agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
      },
      body:
          'cid=$categoryId&timeUnit=date&startDate=$today&endDate=$today&age=&gender=&device=',
    );

    if (response.statusCode != 200) {
      throw NaverApiException(
          'Insight API failed: ${response.statusCode}',
          response.statusCode);
    }

    final json = jsonDecode(response.body) as List<dynamic>;
    if (json.isEmpty) return [];

    final latest = json.last as Map<String, dynamic>;
    final ranks = (latest['ranks'] as List<dynamic>?) ?? [];

    final keywords = ranks.map((r) {
      return PopularKeyword(
        rank: (r['rank'] as num).toInt(),
        keyword: r['keyword'] as String,
        category: categoryName ?? categoryId,
      );
    }).toList();

    _cache.put(cacheKey, keywords);
    return keywords;
  }

  Future<List<PopularKeyword>> fetchAllPopularKeywords() async {
    final cacheKey = 'popular|all';
    final cached = _cache.get<List<PopularKeyword>>(cacheKey);
    if (cached != null) return cached;

    final firestore = await firestoreList(
      CacheKeys.popularKeywordsAll,
      PopularKeyword.fromJson,
    );
    if (firestore != null) {
      _cache.put(cacheKey, firestore);
      return firestore;
    }

    if (kIsWeb) return [];

    final allKeywords = <PopularKeyword>[];
    for (final entry in shoppingCategories.entries) {
      try {
        final keywords = await fetchPopularKeywords(
          categoryId: entry.value,
          categoryName: entry.key,
        );
        allKeywords.addAll(keywords);
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 300));
    }

    _cache.put(cacheKey, allKeywords);
    return allKeywords;
  }

  // ── 딜/BEST100 위임 ──

  Future<List<Product>> fetchTodayDeals() => _dealFetcher.fetchTodayDeals();
  Future<List<Product>> fetchBest100({
    String sortType = 'PRODUCT_CLICK',
    String categoryId = 'A',
  }) =>
      _dealFetcher.fetchBest100(sortType: sortType, categoryId: categoryId);
  Future<List<Product>> fetchShoppingLive() =>
      _dealFetcher.fetchShoppingLive();
  Future<List<Product>> fetchNaverPromotions() =>
      _dealFetcher.fetchNaverPromotions();
  Future<List<Product>> fetch11stDeals() => _dealFetcher.fetch11stDeals();
  Future<List<Product>> fetchGmarketDeals() =>
      _dealFetcher.fetchGmarketDeals();
  Future<List<Product>> fetchAuctionDeals() =>
      _dealFetcher.fetchAuctionDeals();
  Future<List<TrendKeyword>> fetchKeywordRank() =>
      _dealFetcher.fetchKeywordRank();

  void dispose() {
    _client.close();
    _cache.clear();
  }
}
