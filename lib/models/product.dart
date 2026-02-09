class Product {
  final String id;
  final String title;
  final String link;
  final String imageUrl;
  final int currentPrice;
  final int? previousPrice;
  final String mallName;
  final String? brand;
  final String? maker;
  final String category1;
  final String? category2;
  final String? category3;
  final String productType;
  final int? reviewCount;
  final int? purchaseCount;
  final double? reviewScore;
  final int? rank;
  final bool isDeliveryFree;
  final bool isArrivalGuarantee;
  final String? saleEndDate;

  Product({
    required this.id,
    required this.title,
    required this.link,
    required this.imageUrl,
    required this.currentPrice,
    this.previousPrice,
    required this.mallName,
    this.brand,
    this.maker,
    required this.category1,
    this.category2,
    this.category3,
    this.productType = '2',
    this.reviewCount,
    this.purchaseCount,
    this.reviewScore,
    this.rank,
    this.isDeliveryFree = false,
    this.isArrivalGuarantee = false,
    this.saleEndDate,
  });

  double get dropRate {
    if (previousPrice == null || previousPrice == 0) return 0;
    return ((previousPrice! - currentPrice) / previousPrice!) * 100;
  }

  DealBadge? get badge {
    if (id.startsWith('deal_')) return DealBadge.todayDeal;
    if (id.startsWith('best_')) return DealBadge.best100;
    return null;
  }

  /// 네이버 쇼핑 오늘끝딜/스페셜딜 데이터에서 생성
  factory Product.fromTodayDeal(Map<String, dynamic> json) {
    final salePrice = (json['salePrice'] as num?)?.toInt() ?? 0;
    final discountedPrice = (json['discountedPrice'] as num?)?.toInt() ?? salePrice;
    final discountedRatio = (json['discountedRatio'] as num?)?.toInt() ?? 0;

    // labelText에서 상점/딜 타입 추출 (줄바꿈 제거)
    final label = (json['labelText'] as String?)?.replaceAll('\n', ' ').trim() ?? '';

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
      reviewScore: (json['averageReviewScore'] as num?)?.toDouble(),
      reviewCount: (json['totalReviewCount'] as num?)?.toInt(),
      purchaseCount: (json['cumulationSaleCount'] as num?)?.toInt(),
      isDeliveryFree: json['isDeliveryFree'] == true,
      isArrivalGuarantee: json['isArrivalGuarantee'] == true,
      saleEndDate: json['saleEndDate']?.toString(),
    );
  }

  /// 네이버 쇼핑 BEST100 데이터에서 생성
  factory Product.fromBest100(Map<String, dynamic> json) {
    final discountPrice = (json['discountPriceValue'] as num?)?.toInt() ?? 0;
    final originalPrice = (json['priceValue'] as num?)?.toInt() ?? 0;
    final price = discountPrice > 0 ? discountPrice : originalPrice;
    final discountRate = int.tryParse(json['discountRate']?.toString() ?? '0') ?? 0;

    return Product(
      id: 'best_${json['productId']?.toString() ?? ''}',
      title: json['title'] ?? '',
      link: json['linkUrl'] ?? '',
      imageUrl: json['imageUrl'] ?? '',
      currentPrice: price,
      previousPrice: discountRate > 0 ? originalPrice : null,
      mallName: json['mallNm']?.toString() ?? 'BEST100',
      category1: 'BEST100',
      productType: '1',
      reviewCount: int.tryParse(json['reviewCount']?.toString().replaceAll(',', '') ?? ''),
      reviewScore: double.tryParse(json['reviewScore']?.toString() ?? ''),
      rank: (json['rank'] as num?)?.toInt(),
      isDeliveryFree: json['deliveryFeeType'] == 'FREE',
      isArrivalGuarantee: json['isArrivalGuarantee'] == true,
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

enum DealBadge {
  todayDeal('오늘의 특가', '특가'),
  best100('BEST 100', 'BEST');

  final String label;
  final String shortLabel;
  const DealBadge(this.label, this.shortLabel);
}
