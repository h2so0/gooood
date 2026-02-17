import 'product.dart';

/// Firestore 저장용 일별 요약 스냅샷
class KeywordPriceSummary {
  final String date;
  final int minPrice;
  final int maxPrice;
  final int medianPrice;
  final double avgPrice;
  final int resultCount;

  KeywordPriceSummary({
    required this.date,
    required this.minPrice,
    required this.maxPrice,
    required this.medianPrice,
    required this.avgPrice,
    required this.resultCount,
  });

  Map<String, dynamic> toJson() => {
        'date': date,
        'minPrice': minPrice,
        'maxPrice': maxPrice,
        'medianPrice': medianPrice,
        'avgPrice': avgPrice,
        'resultCount': resultCount,
      };

  factory KeywordPriceSummary.fromJson(Map<String, dynamic> json) =>
      KeywordPriceSummary(
        date: json['date'] as String,
        minPrice: (json['minPrice'] as num).toInt(),
        maxPrice: (json['maxPrice'] as num).toInt(),
        medianPrice: (json['medianPrice'] as num).toInt(),
        avgPrice: (json['avgPrice'] as num).toDouble(),
        resultCount: (json['resultCount'] as num).toInt(),
      );
}

/// 실시간 API 분석용 상세 스냅샷 (로컬 전용)
class KeywordPriceSnapshot {
  final String date;
  final int minPrice;
  final int maxPrice;
  final int medianPrice;
  final double avgPrice;
  final int resultCount;
  final List<PriceBucket> buckets;

  KeywordPriceSnapshot({
    required this.date,
    required this.minPrice,
    required this.maxPrice,
    required this.medianPrice,
    required this.avgPrice,
    required this.resultCount,
    required this.buckets,
  });

  KeywordPriceSummary toSummary() => KeywordPriceSummary(
        date: date,
        minPrice: minPrice,
        maxPrice: maxPrice,
        medianPrice: medianPrice,
        avgPrice: avgPrice,
        resultCount: resultCount,
      );

  /// 최저가 판매자 (첫 번째 버킷의 첫 seller)
  SellerInBucket? get cheapestSeller {
    for (final bucket in buckets) {
      if (bucket.sellers.isNotEmpty) return bucket.sellers.first;
    }
    return null;
  }
}

/// 히스토그램 버킷
class PriceBucket {
  final int rangeStart;
  final int rangeEnd;
  final int count;
  final List<SellerInBucket> sellers;

  PriceBucket({
    required this.rangeStart,
    required this.rangeEnd,
    required this.count,
    required this.sellers,
  });

  String get label {
    if (rangeStart >= 10000) {
      final startMan = rangeStart / 10000;
      final endMan = rangeEnd / 10000;
      final startStr = startMan == startMan.roundToDouble()
          ? '${startMan.toInt()}만'
          : '${startMan.toStringAsFixed(1)}만';
      final endStr = endMan == endMan.roundToDouble()
          ? '${endMan.toInt()}만'
          : '${endMan.toStringAsFixed(1)}만';
      return '$startStr~$endStr';
    }
    return '${(rangeStart / 1000).toStringAsFixed(0)}천~${(rangeEnd / 1000).toStringAsFixed(0)}천';
  }
}

/// 버킷 내 개별 판매처
class SellerInBucket {
  final String productId;
  final String title;
  final String mallName;
  final int price;
  final String link;
  final String imageUrl;
  final double? reviewScore;
  final int? reviewCount;

  SellerInBucket({
    required this.productId,
    required this.title,
    required this.mallName,
    required this.price,
    required this.link,
    required this.imageUrl,
    this.reviewScore,
    this.reviewCount,
  });

  Product toProduct() => Product(
        id: productId,
        title: title,
        link: link,
        imageUrl: imageUrl,
        currentPrice: price,
        mallName: mallName,
        category1: '',
        reviewScore: reviewScore,
        reviewCount: reviewCount,
      );
}
