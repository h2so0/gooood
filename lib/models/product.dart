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
  final String? subCategory;
  final String productType;
  final int? reviewCount;
  final int? purchaseCount;
  final double? reviewScore;
  final int? rank;
  final bool isDeliveryFree;
  final bool isArrivalGuarantee;
  final String? saleEndDate;
  final List<String>? searchKeywords;

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
    this.subCategory,
    this.productType = '2',
    this.reviewCount,
    this.purchaseCount,
    this.reviewScore,
    this.rank,
    this.isDeliveryFree = false,
    this.isArrivalGuarantee = false,
    this.saleEndDate,
    this.searchKeywords,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'link': link,
    'imageUrl': imageUrl,
    'currentPrice': currentPrice,
    'previousPrice': previousPrice,
    'mallName': mallName,
    'brand': brand,
    'maker': maker,
    'category1': category1,
    'category2': category2,
    'category3': category3,
    'subCategory': subCategory,
    'productType': productType,
    'reviewCount': reviewCount,
    'purchaseCount': purchaseCount,
    'reviewScore': reviewScore,
    'rank': rank,
    'isDeliveryFree': isDeliveryFree,
    'isArrivalGuarantee': isArrivalGuarantee,
    'saleEndDate': saleEndDate,
    'searchKeywords': searchKeywords,
  };

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  factory Product.fromJson(Map<String, dynamic> json) => Product(
    id: json['id']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
    link: json['link']?.toString() ?? '',
    imageUrl: json['imageUrl']?.toString() ?? '',
    currentPrice: _toInt(json['currentPrice']) ?? 0,
    previousPrice: _toInt(json['previousPrice']),
    mallName: json['mallName']?.toString() ?? '',
    brand: json['brand']?.toString(),
    maker: json['maker']?.toString(),
    category1: json['category1']?.toString() ?? '',
    category2: json['category2']?.toString(),
    category3: json['category3']?.toString(),
    subCategory: json['subCategory']?.toString(),
    productType: json['productType']?.toString() ?? '2',
    reviewCount: _toInt(json['reviewCount']),
    purchaseCount: _toInt(json['purchaseCount']),
    reviewScore: _toDouble(json['reviewScore']),
    rank: _toInt(json['rank']),
    isDeliveryFree: json['isDeliveryFree'] == true,
    isArrivalGuarantee: json['isArrivalGuarantee'] == true,
    saleEndDate: json['saleEndDate']?.toString(),
    searchKeywords: (json['searchKeywords'] as List<dynamic>?)
        ?.map((e) => e.toString())
        .toList(),
  );

  Product copyWith({
    String? id,
    String? title,
    String? link,
    String? imageUrl,
    int? currentPrice,
    int? previousPrice,
    String? mallName,
    String? brand,
    String? maker,
    String? category1,
    String? category2,
    String? category3,
    String? subCategory,
    String? productType,
    int? reviewCount,
    int? purchaseCount,
    double? reviewScore,
    int? rank,
    bool? isDeliveryFree,
    bool? isArrivalGuarantee,
    String? saleEndDate,
    List<String>? searchKeywords,
  }) {
    return Product(
      id: id ?? this.id,
      title: title ?? this.title,
      link: link ?? this.link,
      imageUrl: imageUrl ?? this.imageUrl,
      currentPrice: currentPrice ?? this.currentPrice,
      previousPrice: previousPrice ?? this.previousPrice,
      mallName: mallName ?? this.mallName,
      brand: brand ?? this.brand,
      maker: maker ?? this.maker,
      category1: category1 ?? this.category1,
      category2: category2 ?? this.category2,
      category3: category3 ?? this.category3,
      subCategory: subCategory ?? this.subCategory,
      productType: productType ?? this.productType,
      reviewCount: reviewCount ?? this.reviewCount,
      purchaseCount: purchaseCount ?? this.purchaseCount,
      reviewScore: reviewScore ?? this.reviewScore,
      rank: rank ?? this.rank,
      isDeliveryFree: isDeliveryFree ?? this.isDeliveryFree,
      isArrivalGuarantee: isArrivalGuarantee ?? this.isArrivalGuarantee,
      saleEndDate: saleEndDate ?? this.saleEndDate,
      searchKeywords: searchKeywords ?? this.searchKeywords,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Product && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  double get dropRate {
    if (previousPrice == null || previousPrice == 0) return 0;
    return ((previousPrice! - currentPrice) / previousPrice!) * 100;
  }

  /// 화면에 표시할 판매처명 (네이버 상품은 "네이버"로 통일)
  String get displayMallName {
    if (id.startsWith('deal_') ||
        id.startsWith('best_') ||
        id.startsWith('live_') ||
        id.startsWith('promo_')) {
      return '네이버';
    }
    if (id.startsWith('11st_')) return '11번가';
    if (id.startsWith('gmkt_')) return 'G마켓';
    if (id.startsWith('auction_')) return '옥션';
    if (id.startsWith('lotte_')) return '롯데ON';
    if (id.startsWith('ssg_')) return 'SSG';
    return mallName;
  }

  DealBadge? get badge {
    if (id.startsWith('deal_')) return DealBadge.todayDeal;
    if (id.startsWith('best_')) return DealBadge.best100;
    if (id.startsWith('live_')) return DealBadge.shoppingLive;
    if (id.startsWith('promo_')) return DealBadge.naverPromo;
    if (id.startsWith('11st_')) return DealBadge.st11;
    if (id.startsWith('gmkt_')) return DealBadge.gmarket;
    if (id.startsWith('auction_')) return DealBadge.auction;
    if (id.startsWith('lotte_')) return DealBadge.lotteon;
    if (id.startsWith('ssg_')) return DealBadge.ssg;
    return null;
  }

  static String _decodeHtmlEntities(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
  }

  factory Product.fromNaverApi(Map<String, dynamic> json) {
    final title = _decodeHtmlEntities(
        (json['title'] as String).replaceAll(RegExp(r'<[^>]*>'), ''));
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
  todayDeal('오늘의 특가', '네이버'),
  best100('BEST 100', '네이버'),
  shoppingLive('쇼핑라이브', '네이버'),
  naverPromo('네이버 프로모션', '네이버'),
  st11('11번가', '11번가'),
  gmarket('G마켓', 'G마켓'),
  auction('옥션', '옥션'),
  lotteon('롯데ON', '롯데ON'),
  ssg('SSG', 'SSG');

  final String label;
  final String shortLabel;
  const DealBadge(this.label, this.shortLabel);
}
