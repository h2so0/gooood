import 'dart:math' show max;
import '../models/product.dart';

/// 제외: 통신사/약정/중고/렌탈/구독
const blacklistKeywords = [
  '번호이동', '기기변경', '약정', '공시지원', '선택약정',
  'SKT', 'KT ', 'LGU+', 'LG U+', '알뜰폰', '중고폰',
  '리퍼', '공기계', '샘플', '테스트',
  // 렌탈/구독 확장
  '대여', '렌탈', '렌트', '임대',
  '월렌탈', '월 렌탈', '월임대', '월 임대',
  '월납입', '납입금', '의무사용', '약정기간', '등록비',
  '렌탈료', '임대료', '케어십', '케어솔루션', '구독',
  '방문관리', '자가관리', '중고',
];

/// 제외: 부품/단품/액세서리
const partKeywords = [
  '한쪽', '단품', '유닛', '충전기 단품', '본체 단품',
  '왼쪽', '오른쪽', '교체용', '호환', '케이스만',
  // 확장
  '충전기만', '어댑터만', '케이블만', '리모컨만',
  '필터만', '소모품', '부속', '부품',
  '보호필름', '거치대', '이어팁', '이어캡', '헤드만',
  '액세서리', '악세사리', '교체형', '리필', '리필용',
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

/// 렌탈/구독 가격 패턴 정규식
final _rentalPricePattern = RegExp(
  r'월\s*[\d,]+\s*원|'          // 월 39,900원
  r'[\d,]+\s*원\s*/\s*월|'      // 39,900원/월
  r'\d+\s*개월\s*약정|'          // 36개월 약정
  r'의무\s*사용\s*\d+|'          // 의무사용 36
  r'등록비\s*[\d,]+|'            // 등록비 100,000
  r'월\s*[\d,]+\s*₩|'           // 월 39,900₩
  r'렌탈\s*기간|'                // 렌탈 기간
  r'약정\s*\d+\s*년',            // 약정 3년
  caseSensitive: false,
);

/// 기본 필터 (쓰레기 제거)
List<Product> filterProducts(List<Product> products) {
  return products.where((p) {
    if (p.currentPrice <= 0) return false;
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

/// 렌탈 패턴 감지 (제목에서 가격패턴 정규식 매칭)
bool isRentalProduct(Product p) {
  return _rentalPricePattern.hasMatch(p.title);
}

/// 렌탈 패턴 필터링
List<Product> filterRentalProducts(List<Product> products) {
  return products.where((p) => !isRentalProduct(p)).toList();
}

/// 카테고리 기반 관련성 필터
/// 원본 상품의 category3 (또는 category2)와 일치하는 상품만 통과.
/// 카테고리 정보가 없는 상품은 통과 (benefit of the doubt).
List<Product> filterByCategory(List<Product> products, Product original) {
  final origCat3 = original.category3;
  final origCat2 = original.category2;

  // 원본 자체에 카테고리가 없으면 필터링 불가 → 전부 통과
  if ((origCat3 == null || origCat3.isEmpty) &&
      (origCat2 == null || origCat2.isEmpty)) {
    return products;
  }

  return products.where((p) {
    // 검색 결과 상품에 카테고리 정보가 없으면 통과
    if ((p.category3 == null || p.category3!.isEmpty) &&
        (p.category2 == null || p.category2!.isEmpty)) {
      return true;
    }

    // category3 일치 우선
    if (origCat3 != null &&
        origCat3.isNotEmpty &&
        p.category3 != null &&
        p.category3!.isNotEmpty) {
      return p.category3 == origCat3;
    }

    // category3이 없으면 category2로 비교
    if (origCat2 != null &&
        origCat2.isNotEmpty &&
        p.category2 != null &&
        p.category2!.isNotEmpty) {
      return p.category2 == origCat2;
    }

    return true;
  }).toList();
}

/// 키워드 토큰 관련성 필터
/// 키워드의 주요 토큰 중 절반 이상이 상품 제목에 포함되어야 통과.
/// 1글자 이하 토큰은 무시.
List<Product> filterByKeywordRelevance(
    List<Product> products, String keyword) {
  // "외", "세트", "묶음" 등 의미 없는 접미어 제거
  final cleaned = keyword.replaceAll(RegExp(r'\s+(외|세트|묶음|패키지)\s*$'), '');
  final tokens = cleaned
      .split(RegExp(r'\s+'))
      .where((t) => t.length > 1)
      .toList();

  if (tokens.isEmpty) return products;

  final threshold = (tokens.length / 2).ceil(); // 절반 이상 매칭

  return products.where((p) {
    final title = p.title;
    final matchCount = tokens.where((token) => title.contains(token)).length;
    return matchCount >= threshold;
  }).toList();
}

/// 가격 이상치 제거 (IQR 방식)
/// 5개 미만이면 적용하지 않음.
List<Product> filterPriceOutliers(List<Product> products) {
  if (products.length < 5) return products;

  final prices = products.map((p) => p.currentPrice).toList()..sort();
  final n = prices.length;

  final q1 = prices[n ~/ 4];
  final q3 = prices[(n * 3) ~/ 4];
  final iqr = q3 - q1;
  final factor = 2.0;

  final lowerBound = (q1 - iqr * factor).toInt();
  final upperBound = (q3 + iqr * factor).toInt();

  return products.where((p) {
    return p.currentPrice >= max(0, lowerBound) &&
        p.currentPrice <= upperBound;
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
