import '../constants/category_data.dart';

/// 크로스 소스 중복 제거용: prefix를 제거한 순수 ID 추출
/// 네이버 소스(deal_/best_/live_/promo_)와 G마켓/옥션(gmkt_/auction_)은
/// 같은 상품이 다른 prefix로 존재할 수 있음
String? extractRawId(String id) {
  for (final prefix in ['deal_', 'best_', 'live_', 'promo_']) {
    if (id.startsWith(prefix)) return 'naver_${id.substring(prefix.length)}';
  }
  if (id.startsWith('gmkt_')) return 'gianex_${id.substring(5)}';
  if (id.startsWith('auction_')) return 'gianex_${id.substring(8)}';
  return null;
}

/// 네이버 category1/2/3 → 앱 카테고리 매핑
String? mapToAppCategory(String cat1, [String? cat2, String? cat3]) {
  final sub = '${cat2 ?? ''} ${cat3 ?? ''}'.trim();
  if (sub.contains('반려') || sub.contains('애완') || sub.contains('펫')) {
    return '반려동물';
  }
  if (cat1.contains('디지털') || cat1.contains('가전') || cat1.contains('컴퓨터') ||
      cat1.contains('휴대폰') || cat1.contains('게임')) {
    return '디지털/가전';
  }
  if (cat1.contains('패션') || cat1.contains('의류') || cat1.contains('잡화')) {
    return '패션/의류';
  }
  if (cat1.contains('화장품') || cat1.contains('미용') || cat1.contains('뷰티')) {
    return '뷰티';
  }
  if (cat1.contains('식품') || cat1.contains('음료')) {
    return '식품';
  }
  if (cat1.contains('스포츠') || cat1.contains('레저')) {
    return '스포츠/레저';
  }
  if (cat1.contains('출산') || cat1.contains('육아') || cat1.contains('유아')) {
    return '출산/육아';
  }
  if (cat1.contains('생활') || cat1.contains('건강') || cat1.contains('가구') ||
      cat1.contains('인테리어') || cat1.contains('주방') || cat1.contains('문구')) {
    return '생활/건강';
  }
  return null;
}

/// 상품 제목 기반 로컬 키워드 매칭으로 카테고리 분류 (API 호출 0회)
String? classifyByTitle(String title) {
  final lower = title.toLowerCase();
  for (final entry in categoryKeywords.entries) {
    for (final keyword in entry.value) {
      if (lower.contains(keyword.toLowerCase())) {
        return entry.key;
      }
    }
  }
  return null;
}
