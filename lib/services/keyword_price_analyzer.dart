import 'package:intl/intl.dart';
import '../models/keyword_price_data.dart';
import '../models/product.dart';
import 'naver_shopping_api.dart';
import 'product_filter.dart';

class KeywordPriceAnalyzer {
  final NaverShoppingApi _api;

  KeywordPriceAnalyzer(this._api);

  /// 키워드로 실시간 가격 분석 (API 100개 조회 → 다층 필터링 → 분석)
  ///
  /// [originalProduct]가 있으면 카테고리 필터도 적용.
  Future<KeywordPriceSnapshot> analyze(
    String keyword, {
    Product? originalProduct,
  }) async {
    final raw = await _api.search(
      query: keyword,
      display: 100,
      sort: 'sim',
    );

    // 다층 필터링 파이프라인
    var products = filterProducts(raw);         // 기존+확장: 가격0, 통신사, 중고, 렌탈 제거
    products = filterParts(products);            // 기존+확장: 부품/액세서리 제거
    products = filterRentalProducts(products);   // 신규: 정규식 렌탈 패턴 제거
    products = filterByKeywordRelevance(products, keyword); // 신규: 키워드 토큰 전체 포함
    if (originalProduct != null) {
      products = filterByCategory(products, originalProduct); // 신규: 카테고리 필터
    }
    products = filterPriceOutliers(products);    // 신규: IQR 이상치 제거

    if (products.isEmpty) {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      return KeywordPriceSnapshot(
        date: today,
        minPrice: 0,
        maxPrice: 0,
        medianPrice: 0,
        avgPrice: 0,
        resultCount: 0,
        buckets: [],
      );
    }

    products.sort((a, b) => a.currentPrice.compareTo(b.currentPrice));

    final prices = products.map((p) => p.currentPrice).toList();
    final minP = prices.first;
    final maxP = prices.last;
    final medianP = prices[prices.length ~/ 2];
    final avgP = prices.reduce((a, b) => a + b) / prices.length;

    final buckets = _buildBuckets(products, minP, maxP);
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    return KeywordPriceSnapshot(
      date: today,
      minPrice: minP,
      maxPrice: maxP,
      medianPrice: medianP,
      avgPrice: avgP,
      resultCount: products.length,
      buckets: buckets,
    );
  }

  List<PriceBucket> _buildBuckets(List<Product> products, int minP, int maxP) {
    final range = maxP - minP;
    if (range == 0) {
      return [
        PriceBucket(
          rangeStart: minP,
          rangeEnd: maxP,
          count: products.length,
          sellers: _topSellers(products),
        ),
      ];
    }

    final bucketSize = _bucketSize(maxP);
    final alignedStart = (minP ~/ bucketSize) * bucketSize;

    final bucketMap = <int, List<Product>>{};
    for (final p in products) {
      final key = ((p.currentPrice - alignedStart) ~/ bucketSize) * bucketSize +
          alignedStart;
      bucketMap.putIfAbsent(key, () => []).add(p);
    }

    final sortedKeys = bucketMap.keys.toList()..sort();

    // 최대 8개 버킷으로 제한
    if (sortedKeys.length > 8) {
      final merged = <int, List<Product>>{};
      final step = (sortedKeys.length / 8).ceil();
      for (int i = 0; i < sortedKeys.length; i += step) {
        final groupKeys = sortedKeys.sublist(
            i, (i + step).clamp(0, sortedKeys.length));
        final first = groupKeys.first;
        final all = <Product>[];
        for (final k in groupKeys) {
          all.addAll(bucketMap[k]!);
        }
        merged[first] = all;
      }
      return merged.entries.map((e) {
        final last = e.key + bucketSize * ((sortedKeys.length / 8).ceil());
        return PriceBucket(
          rangeStart: e.key,
          rangeEnd: last.clamp(e.key + bucketSize, maxP + bucketSize),
          count: e.value.length,
          sellers: _topSellers(e.value),
        );
      }).toList();
    }

    return sortedKeys.map((key) {
      final items = bucketMap[key]!;
      return PriceBucket(
        rangeStart: key,
        rangeEnd: key + bucketSize,
        count: items.length,
        sellers: _topSellers(items),
      );
    }).toList();
  }

  /// 가격대별 버킷 사이즈 자동 스케일링
  int _bucketSize(int maxPrice) {
    if (maxPrice <= 10000) return 2000;
    if (maxPrice <= 50000) return 10000;
    if (maxPrice <= 200000) return 50000;
    if (maxPrice <= 1000000) return 100000;
    return 500000;
  }

  List<SellerInBucket> _topSellers(List<Product> products) {
    final sorted = List<Product>.from(products)
      ..sort((a, b) => a.currentPrice.compareTo(b.currentPrice));
    return sorted.take(5).map((p) {
      return SellerInBucket(
        productId: p.id,
        title: p.title,
        mallName: p.mallName,
        price: p.currentPrice,
        link: p.link,
        imageUrl: p.imageUrl,
        reviewScore: p.reviewScore,
        reviewCount: p.reviewCount,
      );
    }).toList();
  }
}
