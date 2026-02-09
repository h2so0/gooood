class Product {
  final String id;
  final String title;
  final String link;
  final String imageUrl;
  final int currentPrice;
  final int? previousPrice;
  final int? lowestEver;
  final int? highestEver;
  final int? avgPrice;
  final String mallName;
  final String? brand;
  final String? maker;
  final String category1;
  final String? category2;
  final String? category3;
  final String productType;
  final List<PricePoint> priceHistory;

  Product({
    required this.id,
    required this.title,
    required this.link,
    required this.imageUrl,
    required this.currentPrice,
    this.previousPrice,
    this.lowestEver,
    this.highestEver,
    this.avgPrice,
    required this.mallName,
    this.brand,
    this.maker,
    required this.category1,
    this.category2,
    this.category3,
    this.productType = '2',
    this.priceHistory = const [],
  });

  double get dropRate {
    if (previousPrice == null || previousPrice == 0) return 0;
    return ((previousPrice! - currentPrice) / previousPrice!) * 100;
  }

  bool get isAllTimeLow =>
      lowestEver != null && currentPrice <= lowestEver!;

  bool get isBigDrop => dropRate >= 15;

  DealBadge? get badge {
    if (isAllTimeLow) return DealBadge.allTimeLow;
    if (dropRate >= 20) return DealBadge.bigDrop;
    if (dropRate >= 10) return DealBadge.drop;
    if (avgPrice != null && currentPrice < avgPrice! * 0.9) {
      return DealBadge.belowAvg;
    }
    return null;
  }

  /// 네이버 쇼핑 오늘끝딜/스페셜딜 데이터에서 생성
  factory Product.fromTodayDeal(Map<String, dynamic> json) {
    final salePrice = (json['salePrice'] as num?)?.toInt() ?? 0;
    final discountedPrice = (json['discountedPrice'] as num?)?.toInt() ?? salePrice;
    final discountedRatio = (json['discountedRatio'] as num?)?.toInt() ?? 0;

    // labelText에서 상점/딜 타입 추출 (줄바꿈 제거)
    final label = (json['labelText'] as String?)?.replaceAll('\n', ' ')?.trim() ?? '';

    return Product(
      id: 'deal_${json['productId']?.toString() ?? ''}',
      title: json['name'] ?? '',
      link: json['landingUrl'] ?? '',
      imageUrl: json['imageUrl'] ?? '',
      currentPrice: discountedRatio > 0 ? discountedPrice : salePrice,
      previousPrice: discountedRatio > 0 ? salePrice : null,
      mallName: label.isNotEmpty ? label : '스마트스토어',
      category1: '오늘의딜',
      productType: '1',
    );
  }

  factory Product.fromNaverApi(Map<String, dynamic> json) {
    final title = (json['title'] as String)
        .replaceAll(RegExp(r'<[^>]*>'), '');
    final lprice = int.tryParse(json['lprice']?.toString() ?? '0') ?? 0;
    final hprice = int.tryParse(json['hprice']?.toString() ?? '0') ?? 0;
    // hprice > lprice 이면 할인율 계산용으로 사용
    final prev = (hprice > lprice) ? hprice : null;
    return Product(
      id: json['productId']?.toString() ?? '',
      title: title,
      link: json['link'] ?? '',
      imageUrl: json['image'] ?? '',
      currentPrice: lprice,
      previousPrice: prev,
      highestEver: prev,
      mallName: json['mallName'] ?? '',
      brand: json['brand'],
      maker: json['maker'],
      category1: json['category1'] ?? '',
      category2: json['category2'],
      category3: json['category3'],
      productType: json['productType']?.toString() ?? '2',
    );
  }
}

class PricePoint {
  final DateTime date;
  final int price;

  const PricePoint({required this.date, required this.price});
}

enum DealBadge {
  allTimeLow('역대 최저가', '최저'),
  bigDrop('급락', '급락'),
  drop('하락', '하락'),
  belowAvg('평균 이하', '저가');

  final String label;
  final String shortLabel;
  const DealBadge(this.label, this.shortLabel);
}
