import '../models/product.dart';

const minPrice = 5000;

/// 제외: 통신사/약정/중고
const blacklistKeywords = [
  '번호이동', '기기변경', '약정', '공시지원', '선택약정',
  'SKT', 'KT ', 'LGU+', 'LG U+', '알뜰폰', '중고폰',
  '리퍼', '공기계', '샘플', '테스트',
  '대여', '렌탈',
];

/// 제외: 부품/단품/액세서리
const partKeywords = [
  '한쪽', '단품', '유닛', '충전기 단품', '본체 단품',
  '왼쪽', '오른쪽', '교체용', '호환', '케이스만',
];

/// 유명 쇼핑몰 (우선 표시)
const majorMalls = [
  '네이버', '쿠팡', '11번가', 'G마켓', '옥션',
  '롯데ON', 'SSG', '현대Hmall', 'CJ온스타일',
  '하이마트', '무신사', '올리브영',
];

/// 유명 브랜드
const majorBrands = [
  'Apple', 'Samsung', 'LG', 'Sony', 'Dyson',
  'Nike', 'Adidas', 'Nintendo', 'Bose',
  '삼성', '엘지', '애플', '소니', '다이슨',
  '나이키', '아디다스', '닌텐도', '보스',
];

/// 기본 필터 (쓰레기 제거)
List<Product> filterProducts(List<Product> products) {
  return products.where((p) {
    if (p.currentPrice < minPrice) return false;
    final title = p.title;
    for (final kw in blacklistKeywords) {
      if (title.contains(kw)) return false;
    }
    return true;
  }).toList();
}

/// 부품/단품 제거
List<Product> filterParts(List<Product> products) {
  return products.where((p) {
    final title = p.title;
    for (final kw in partKeywords) {
      if (title.contains(kw)) return false;
    }
    return true;
  }).toList();
}

/// 유명 브랜드/쇼핑몰 우선 정렬
List<Product> prioritizeQuality(List<Product> products) {
  final sorted = List<Product>.from(products);
  sorted.sort((a, b) {
    final aScore = qualityScore(a);
    final bScore = qualityScore(b);
    return bScore.compareTo(aScore);
  });
  return sorted;
}

int qualityScore(Product p) {
  int score = 0;
  if (p.productType == '1') score += 3;
  final brandLower = (p.brand ?? '').toLowerCase();
  for (final b in majorBrands) {
    if (brandLower.contains(b.toLowerCase())) {
      score += 2;
      break;
    }
  }
  for (final m in majorMalls) {
    if (p.mallName.contains(m)) {
      score += 1;
      break;
    }
  }
  return score;
}

/// 상품 그룹핑 키 생성 (같은 상품 판별)
String groupKey(Product p) {
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
