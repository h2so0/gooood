import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../constants/app_constants.dart';
import '../../models/product.dart';
import '../../models/trend_data.dart';
import '../cache/firestore_cache.dart';
import '../cache/memory_cache.dart';

/// 딜/BEST100 등 서버 캐시 기반 상품 fetch
class DealFetcher {
  final http.Client client;
  final MemoryCache cache;

  DealFetcher({required this.client, required this.cache});

  /// 네이버 쇼핑 오늘끝딜/스페셜딜 실제 핫딜 상품 가져오기
  Future<List<Product>> fetchTodayDeals() async {
    const cacheKey = CacheKeys.todayDeals;
    final cached = cache.get<List<Product>>(cacheKey);
    if (cached != null) return cached;

    // Firestore 캐시
    final firestore =
        await firestoreList<Product>(CacheKeys.todayDeals, Product.fromJson);
    if (firestore != null) {
      cache.put(cacheKey, firestore);
      return firestore;
    }

    // API fallback (웹에서는 CORS로 불가)
    if (kIsWeb) return [];

    final response = await client.get(
      Uri.parse('https://shopping.naver.com/ns/home/today-event'),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
    );

    if (response.statusCode != 200) {
      throw NaverApiException(
          'Today deals page failed: ${response.statusCode}',
          response.statusCode);
    }

    final html = response.body;
    final match = RegExp(
      r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>',
    ).firstMatch(html);

    if (match == null) throw NaverApiException('No __NEXT_DATA__ found', 0);

    final nextData = jsonDecode(match.group(1)!) as Map<String, dynamic>;
    final pageProps =
        (nextData['props'] as Map<String, dynamic>)['pageProps']
            as Map<String, dynamic>;
    final waffleData = pageProps['waffleData'] as Map<String, dynamic>?;
    if (waffleData == null) return [];

    final layers =
        ((waffleData['pageData'] as Map<String, dynamic>)['layers']
            as List<dynamic>?) ?? [];

    final products = <Product>[];
    for (final layer in layers) {
      for (final block in (layer['blocks'] as List<dynamic>?) ?? []) {
        for (final item in (block['items'] as List<dynamic>?) ?? []) {
          for (final content in (item['contents'] as List<dynamic>?) ?? []) {
            final c = content as Map<String, dynamic>;
            if (c.containsKey('productId') && c.containsKey('salePrice')) {
              if (c['isSoldOut'] == true) continue;
              if (c['isRental'] == true) continue;
              products.add(Product.fromTodayDeal(c));
            }
          }
        }
      }
    }

    products.sort((a, b) => b.dropRate.compareTo(a.dropRate));
    cache.put(cacheKey, products);
    return products;
  }

  /// 네이버 쇼핑 BEST100 인기 상품 가져오기
  Future<List<Product>> fetchBest100({
    String sortType = 'PRODUCT_CLICK',
    String categoryId = 'A',
  }) async {
    final cacheKey = 'best100|$sortType|$categoryId';
    final cached = cache.get<List<Product>>(cacheKey);
    if (cached != null) return cached;

    // Firestore 캐시
    final firestore = await firestoreList<Product>(
        CacheKeys.best100(categoryId), Product.fromJson);
    if (firestore != null) {
      cache.put(cacheKey, firestore);
      return firestore;
    }

    if (kIsWeb) return [];

    final response = await client.get(
      Uri.parse(
          'https://snxbest.naver.com/api/v1/snxbest/product/rank'
          '?ageType=ALL&categoryId=$categoryId&sortType=$sortType&periodType=DAILY'),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'application/json',
        'Referer': 'https://snxbest.naver.com/home',
      },
    );

    if (response.statusCode != 200) {
      throw NaverApiException(
          'Best100 API failed: ${response.statusCode}',
          response.statusCode);
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final rawProducts = (json['products'] as List<dynamic>?) ?? [];

    final products = <Product>[];
    for (final item in rawProducts) {
      if (item is Map<String, dynamic> &&
          item.containsKey('productId') &&
          item.containsKey('title')) {
        products.add(Product.fromBest100(item));
      }
    }

    products.sort((a, b) => b.dropRate.compareTo(a.dropRate));
    cache.put(cacheKey, products);
    return products;
  }

  /// 네이버 쇼핑라이브 상품 (Firestore 캐시)
  Future<List<Product>> fetchShoppingLive() =>
      fetchCachedProducts(CacheKeys.shoppingLive, cache);

  /// 네이버 프로모션 (Firestore 캐시)
  Future<List<Product>> fetchNaverPromotions() =>
      fetchCachedProducts(CacheKeys.naverPromotions, cache);

  /// 11번가 딜 (Firestore 캐시)
  Future<List<Product>> fetch11stDeals() =>
      fetchCachedProducts(CacheKeys.st11Deals, cache);

  /// G마켓 슈퍼딜 (Firestore 캐시)
  Future<List<Product>> fetchGmarketDeals() =>
      fetchCachedProducts(CacheKeys.gmarketDeals, cache);

  /// 옥션 딜 (Firestore 캐시)
  Future<List<Product>> fetchAuctionDeals() =>
      fetchCachedProducts(CacheKeys.auctionDeals, cache);

  /// 네이버 BEST 키워드 랭킹 (순위 변동 포함)
  Future<List<TrendKeyword>> fetchKeywordRank() async {
    const cacheKey = CacheKeys.keywordRank;
    final cached = cache.get<List<TrendKeyword>>(cacheKey);
    if (cached != null) return cached;

    final firestore = await firestoreList(
      CacheKeys.keywordRank,
      TrendKeyword.fromJson,
    );
    if (firestore != null) {
      cache.put(cacheKey, firestore);
      return firestore;
    }

    if (kIsWeb) return [];

    final response = await client.get(
      Uri.parse(
          'https://snxbest.naver.com/api/v1/snxbest/keyword/rank'
          '?ageType=ALL&categoryId=A&sortType=KEYWORD_NEW&periodType=WEEKLY'),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'application/json',
        'Referer': 'https://snxbest.naver.com/home',
      },
    );

    if (response.statusCode != 200) {
      throw NaverApiException(
          'Keyword rank API failed: ${response.statusCode}',
          response.statusCode);
    }

    final List<dynamic> rawList = jsonDecode(response.body);
    final keywords = <TrendKeyword>[];

    for (final item in rawList) {
      if (item is Map<String, dynamic>) {
        final title = item['title']?.toString() ?? '';
        if (title.isEmpty) continue;
        final rank = (item['rank'] as num?)?.toInt() ?? 0;
        final fluctuation = (item['rankFluctuation'] as num?)?.toInt() ?? 0;
        final status = item['status']?.toString() ?? 'STABLE';

        int? rankChange;
        if (status == 'NEW') {
          rankChange = null;
        } else {
          rankChange = fluctuation;
        }

        keywords.add(TrendKeyword(
          keyword: title,
          ratio: (20 - rank + 1).toDouble(),
          rankChange: rankChange,
        ));
      }
    }

    cache.put(cacheKey, keywords);
    return keywords;
  }
}
