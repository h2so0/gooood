import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import '../models/product.dart';

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

  static const _minPrice = 5000;

  /// 제외: 통신사/약정/중고
  static const _blacklistKeywords = [
    '번호이동', '기기변경', '약정', '공시지원', '선택약정',
    'SKT', 'KT ', 'LGU+', 'LG U+', '알뜰폰', '중고폰',
    '리퍼', '공기계', '샘플', '테스트',
    '대여', '렌탈',
  ];

  /// 제외: 부품/단품/액세서리
  static const _partKeywords = [
    '한쪽', '단품', '유닛', '충전기 단품', '본체 단품',
    '왼쪽', '오른쪽', '교체용', '호환', '케이스만',
  ];

  /// 유명 쇼핑몰 (우선 표시)
  static const _majorMalls = [
    '네이버', '쿠팡', '11번가', 'G마켓', '옥션',
    '롯데ON', 'SSG', '현대Hmall', 'CJ온스타일',
    '하이마트', '무신사', '올리브영',
  ];

  /// 유명 브랜드
  static const _majorBrands = [
    'Apple', 'Samsung', 'LG', 'Sony', 'Dyson',
    'Nike', 'Adidas', 'Nintendo', 'Bose',
    '삼성', '엘지', '애플', '소니', '다이슨',
    '나이키', '아디다스', '닌텐도', '보스',
  ];

  final http.Client _client;
  final Map<String, _CacheEntry<dynamic>> _cache = {};
  static const _cacheDuration = Duration(minutes: 30);

  NaverShoppingApi({http.Client? client})
      : _client = client ?? http.Client();

  Map<String, String> get _headers => {
        'X-Naver-Client-Id': _clientId,
        'X-Naver-Client-Secret': _clientSecret,
      };

  /// 기본 필터 (쓰레기 제거)
  List<Product> _filterProducts(List<Product> products) {
    return products.where((p) {
      if (p.currentPrice < _minPrice) return false;
      final title = p.title;
      for (final kw in _blacklistKeywords) {
        if (title.contains(kw)) return false;
      }
      return true;
    }).toList();
  }

  /// 부품/단품 제거
  List<Product> _filterParts(List<Product> products) {
    return products.where((p) {
      final title = p.title;
      for (final kw in _partKeywords) {
        if (title.contains(kw)) return false;
      }
      return true;
    }).toList();
  }

  /// 유명 브랜드/쇼핑몰 우선 정렬
  List<Product> _prioritizeQuality(List<Product> products) {
    final sorted = List<Product>.from(products);
    sorted.sort((a, b) {
      final aScore = _qualityScore(a);
      final bScore = _qualityScore(b);
      return bScore.compareTo(aScore);
    });
    return sorted;
  }

  int _qualityScore(Product p) {
    int score = 0;
    if (p.productType == '1') score += 3;
    final brandLower = (p.brand ?? '').toLowerCase();
    for (final b in _majorBrands) {
      if (brandLower.contains(b.toLowerCase())) {
        score += 2;
        break;
      }
    }
    for (final m in _majorMalls) {
      if (p.mallName.contains(m)) {
        score += 1;
        break;
      }
    }
    return score;
  }

  /// 상품 검색 (필터링 + 품질 정렬)
  Future<List<Product>> search({
    required String query,
    int display = 20,
    int start = 1,
    String sort = 'sim',
  }) async {
    final cacheKey = 'shop|$query|$display|$start|$sort';
    final cached = _cache[cacheKey];
    if (cached != null && !cached.isExpired) {
      return cached.data as List<Product>;
    }

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

    final filtered = _prioritizeQuality(_filterProducts(products));
    _cache[cacheKey] = _CacheEntry<List<Product>>(filtered);
    return filtered;
  }

  /// 필터링된 검색 (부품/단품 제거)
  Future<List<Product>> searchClean({
    required String query,
    int display = 40,
  }) async {
    final raw = await search(query: query, display: display, sort: 'sim');
    return _filterParts(raw);
  }

  /// 가격 비교 검색: 같은 상품의 판매자별 가격을 비교해서
  /// 최고가를 previousPrice로 설정 → 할인율 자동 계산
  Future<List<Product>> searchWithPriceCompare({
    required String query,
    int display = 100,
  }) async {
    final raw = await search(query: query, display: display, sort: 'sim');
    final filtered = _filterParts(_filterProducts(raw));

    // 같은 상품 그룹핑 (productId 또는 정규화된 제목)
    final groups = <String, List<Product>>{};
    for (final p in filtered) {
      final key = _groupKey(p);
      groups.putIfAbsent(key, () => []).add(p);
    }

    final results = <Product>[];
    for (final group in groups.values) {
      if (group.length < 2) {
        // 단일 판매자 → 비교 불가, 그대로 추가
        results.add(group.first);
        continue;
      }

      // 가격순 정렬
      group.sort((a, b) => a.currentPrice.compareTo(b.currentPrice));
      final cheapest = group.first;
      final mostExpensive = group.last;

      // 최저가와 최고가 차이가 의미있을 때만 (5% 이상)
      final spread =
          (mostExpensive.currentPrice - cheapest.currentPrice) /
              mostExpensive.currentPrice *
              100;

      if (spread >= 5) {
        // 최저가 상품에 최고가를 previousPrice로 설정
        results.add(Product(
          id: cheapest.id,
          title: cheapest.title,
          link: cheapest.link,
          imageUrl: cheapest.imageUrl,
          currentPrice: cheapest.currentPrice,
          previousPrice: mostExpensive.currentPrice,
          mallName: cheapest.mallName,
          brand: cheapest.brand,
          maker: cheapest.maker,
          category1: cheapest.category1,
          category2: cheapest.category2,
          category3: cheapest.category3,
          productType: cheapest.productType,
        ));
      } else {
        results.add(cheapest);
      }
    }

    // 할인율 높은 순 정렬
    results.sort((a, b) => b.dropRate.compareTo(a.dropRate));
    return results;
  }

  /// 상품 그룹핑 키 생성 (같은 상품 판별)
  String _groupKey(Product p) {
    // 카탈로그 상품은 productId로 그룹
    if (p.productType == '1' && p.id.isNotEmpty) return 'cat_${p.id}';

    // 개별 상품은 제목 정규화로 그룹
    var title = p.title.toLowerCase();
    // 쇼핑몰별 접미사 제거
    title = title.replaceAll(RegExp(r'\[[^\]]*\]'), '');
    title = title.replaceAll(RegExp(r'\([^)]*\)'), '');
    // 공백/특수문자 정리
    title = title.replaceAll(RegExp(r'[^가-힣a-z0-9]'), '');
    // 앞 20자만 비교 (모델명 기준)
    if (title.length > 20) title = title.substring(0, 20);
    return 'title_$title';
  }

  /// 검색어 트렌드 조회
  Future<List<TrendKeyword>> fetchSearchTrends({
    required List<String> keywords,
  }) async {
    final cacheKey = 'trend|${keywords.join(",")}';
    final cached = _cache[cacheKey];
    if (cached != null && !cached.isExpired) {
      return cached.data as List<TrendKeyword>;
    }

    final now = DateTime.now();
    final startDate =
        now.subtract(const Duration(days: 14)).toIso8601String().split('T')[0];
    final endDate = now.toIso8601String().split('T')[0];

    final groups =
        keywords.map((k) => {'groupName': k, 'keywords': [k]}).toList();

    final response = await _client.post(
      Uri.parse(_trendUrl),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'startDate': startDate,
        'endDate': endDate,
        'timeUnit': 'week',
        'keywordGroups': groups,
      }),
    );

    if (response.statusCode != 200) {
      throw NaverApiException(
          'Trend API failed: ${response.statusCode}', response.statusCode);
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final results = (json['results'] as List<dynamic>?) ?? [];

    final trends = results.map((r) {
      final data = (r['data'] as List<dynamic>?) ?? [];
      final lastRatio =
          data.isNotEmpty ? (data.last['ratio'] as num).toDouble() : 0.0;
      return TrendKeyword(keyword: r['title'] as String, ratio: lastRatio);
    }).toList();

    trends.sort((a, b) => b.ratio.compareTo(a.ratio));
    _cache[cacheKey] = _CacheEntry<List<TrendKeyword>>(trends);
    return trends;
  }

  /// 트렌드 차트 데이터 (주간 추이 포인트)
  Future<Map<String, List<TrendChartPoint>>> fetchTrendChart({
    required List<Map<String, dynamic>> keywordGroups,
    required String startDate,
    required String endDate,
  }) async {
    final cacheKey = 'chart|$startDate|${keywordGroups.map((g) => g['groupName']).join(",")}';
    final cached = _cache[cacheKey];
    if (cached != null && !cached.isExpired) {
      return cached.data as Map<String, List<TrendChartPoint>>;
    }

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
    final results = (json['results'] as List<dynamic>?) ?? [];

    final chartData = <String, List<TrendChartPoint>>{};
    for (final r in results) {
      final name = r['title'] as String;
      final data = (r['data'] as List<dynamic>?) ?? [];
      chartData[name] = data
          .map((d) => TrendChartPoint(
                period: d['period'] as String,
                ratio: (d['ratio'] as num).toDouble(),
              ))
          .toList();
    }

    _cache[cacheKey] = _CacheEntry<Map<String, List<TrendChartPoint>>>(chartData);
    return chartData;
  }

  /// 쇼핑인사이트: 카테고리별 실시간 인기 검색어 (네이버 실제 유저 데이터)
  Future<List<PopularKeyword>> fetchPopularKeywords({
    required String categoryId,
    String? categoryName,
  }) async {
    final cacheKey = 'popular|$categoryId';
    final cached = _cache[cacheKey];
    if (cached != null && !cached.isExpired) {
      return cached.data as List<PopularKeyword>;
    }

    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final response = await _client.post(
      Uri.parse(_insightUrl),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Referer': 'https://datalab.naver.com/shoppingInsight/sCategory.naver',
        'User-Agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
      },
      body: 'cid=$categoryId&timeUnit=date&startDate=$today&endDate=$today&age=&gender=&device=',
    );

    if (response.statusCode != 200) {
      throw NaverApiException(
          'Insight API failed: ${response.statusCode}', response.statusCode);
    }

    final json = jsonDecode(response.body) as List<dynamic>;
    if (json.isEmpty) return [];

    // 가장 최근 날짜의 랭킹 사용
    final latest = json.last as Map<String, dynamic>;
    final ranks = (latest['ranks'] as List<dynamic>?) ?? [];

    final keywords = ranks.map((r) {
      return PopularKeyword(
        rank: (r['rank'] as num).toInt(),
        keyword: r['keyword'] as String,
        category: categoryName ?? categoryId,
      );
    }).toList();

    _cache[cacheKey] = _CacheEntry<List<PopularKeyword>>(keywords);
    return keywords;
  }

  /// 전체 카테고리 인기 검색어 한 번에 가져오기
  Future<List<PopularKeyword>> fetchAllPopularKeywords() async {
    final cacheKey = 'popular|all';
    final cached = _cache[cacheKey];
    if (cached != null && !cached.isExpired) {
      return cached.data as List<PopularKeyword>;
    }

    final allKeywords = <PopularKeyword>[];

    for (final entry in shoppingCategories.entries) {
      try {
        final keywords = await fetchPopularKeywords(
          categoryId: entry.value,
          categoryName: entry.key,
        );
        allKeywords.addAll(keywords);
      } catch (_) {}
      // rate limit 방지
      await Future.delayed(const Duration(milliseconds: 300));
    }

    _cache[cacheKey] = _CacheEntry<List<PopularKeyword>>(allKeywords);
    return allKeywords;
  }

  /// 네이버 쇼핑 오늘끝딜/스페셜딜 실제 핫딜 상품 가져오기
  /// (shopping.naver.com/ns/home/today-event 의 __NEXT_DATA__ 파싱)
  Future<List<Product>> fetchTodayDeals() async {
    const cacheKey = 'todayDeals';
    final cached = _cache[cacheKey];
    if (cached != null && !cached.isExpired) {
      return cached.data as List<Product>;
    }

    final response = await _client.get(
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
              // 품절 제외
              if (c['isSoldOut'] == true) continue;
              // 렌탈 제외
              if (c['isRental'] == true) continue;
              products.add(Product.fromTodayDeal(c));
            }
          }
        }
      }
    }

    // 할인율 높은 순 정렬
    products.sort((a, b) => b.dropRate.compareTo(a.dropRate));

    _cache[cacheKey] = _CacheEntry<List<Product>>(products);
    return products;
  }

  /// 네이버 쇼핑 BEST100 인기 상품 가져오기 (JSON API)
  /// sortType: PRODUCT_CLICK(클릭순) 또는 PRODUCT_BUY(구매순)
  Future<List<Product>> fetchBest100({
    String sortType = 'PRODUCT_CLICK',
  }) async {
    final cacheKey = 'best100|$sortType';
    final cached = _cache[cacheKey];
    if (cached != null && !cached.isExpired) {
      return cached.data as List<Product>;
    }

    final response = await _client.get(
      Uri.parse(
          'https://snxbest.naver.com/api/v1/snxbest/product/rank'
          '?ageType=ALL&categoryId=A&sortType=$sortType&periodType=DAILY'),
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

    // 첫 번째 아이템 디버그 로그 (reviewCount, purchaseCount 등 필드 확인)
    if (rawProducts.isNotEmpty) {
      developer.log(
        'Best100 first item keys: ${(rawProducts.first as Map<String, dynamic>).keys.toList()}',
        name: 'NaverShoppingApi',
      );
    }

    final products = <Product>[];
    for (final item in rawProducts) {
      if (item is Map<String, dynamic> &&
          item.containsKey('productId') &&
          item.containsKey('title')) {
        products.add(Product.fromBest100(item));
      }
    }

    products.sort((a, b) => b.dropRate.compareTo(a.dropRate));

    _cache[cacheKey] = _CacheEntry<List<Product>>(products);
    return products;
  }

  /// 네이버 BEST 키워드 랭킹 (순위 변동 포함)
  Future<List<TrendKeyword>> fetchKeywordRank() async {
    const cacheKey = 'keywordRank';
    final cached = _cache[cacheKey];
    if (cached != null && !cached.isExpired) {
      return cached.data as List<TrendKeyword>;
    }

    final response = await _client.get(
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

        // rankFluctuation: 양수=이전보다 순위가 올라감
        // status: NEW=신규진입, STABLE=변동없음, UP=상승, DOWN=하락
        int? rankChange;
        if (status == 'NEW') {
          rankChange = null; // 신규
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

    _cache[cacheKey] = _CacheEntry<List<TrendKeyword>>(keywords);
    return keywords;
  }

  void dispose() {
    _client.close();
    _cache.clear();
  }
}

class TrendChartPoint {
  final String period;
  final double ratio;
  const TrendChartPoint({required this.period, required this.ratio});
}

class TrendKeyword {
  final String keyword;
  final double ratio;
  /// 순위 변동: 양수=상승, 음수=하락, 0=변동없음, null=신규
  final int? rankChange;
  const TrendKeyword({
    required this.keyword,
    required this.ratio,
    this.rankChange,
  });
}

class PopularKeyword {
  final int rank;
  final String keyword;
  final String category;
  const PopularKeyword({
    required this.rank,
    required this.keyword,
    required this.category,
  });
}

class _CacheEntry<T> {
  final T data;
  final DateTime createdAt;
  _CacheEntry(this.data) : createdAt = DateTime.now();
  bool get isExpired =>
      DateTime.now().difference(createdAt) > NaverShoppingApi._cacheDuration;
}

class NaverApiException implements Exception {
  final String message;
  final int statusCode;
  NaverApiException(this.message, this.statusCode);
  @override
  String toString() => 'NaverApiException($statusCode): $message';
}
