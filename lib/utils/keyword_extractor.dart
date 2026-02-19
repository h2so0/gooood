import '../models/product.dart';

/// 노이즈 단어 (필터링 대상)
const _noiseWords = {
  '정품', '새상품', '무료배송', '특가', '할인', '자급제', '공식', '인증',
  '빠른배송', '즉시발송', '사은품', '국내정발', '당일출고', '공식판매',
  '추가금없음', '관부가세포함', '무관부가세', '국내배송', '해외직구',
  '병행수입', '한국판', '글로벌', '국내', '해외', '예약', '예약판매',
  '신품', '미개봉', '미개봉정품', '공식정품', '단독특가', '긴급', '한정',
  '국내산', '수입산', '산지직송', '핫딜', '최저가', '파격', '초특가',
  '세일', '대박', '득템', '한정수량', '무료', '증정', '오늘만',
};

/// 서술적 단어 (제품 정체성이 아닌 기능/수식어)
const _descriptorWords = {
  '무선', '유선', '블루투스', '노이즈캔슬링', '통화', '방수', '충전', '대용량',
  '초경량', '접이식', '휴대용', '자동', '수동', '터치', '고급', '프리미엄',
  '신형', '최신', '신제품', '올인원', '완전', '초고속', '저소음', '고성능',
  '듀얼', '트리플', '쿼드', '와이드', '슬림', '미니', '맥스', '플러스',
  '포터블', '스마트', '디지털', '아날로그', '초슬림', '초소형', '대형',
  '고화질', '초고화질', '저전력', '고속', '급속', '일체형', '분리형',
  '방진', '방습', '생활방수', '완전방수', '멀티', '다기능',
  '고농축', '초고농축', '저자극', '친환경', '유기농', '무첨가', '저칼로리',
  '고단백', '무설탕', '무가당', '저지방', '고칼슘', '천연', '순수',
};

/// 용도/맥락 단어 (제품 정체성이 아닌 사용 환경·용도)
const _usageContextWords = {
  '세탁', '실내건조', '드럼', '일반겸용', '리필', '본품', '단품',
  '세트', '묶음', '번들', '패키지', '기획', '기획세트',
  '겸용', '전용', '호환', '교체용', '리필용', '충전용',
  '가정용', '업소용', '사무용', '캠핑용', '차량용', '실내용', '실외용',
  '주방', '욕실', '거실', '침실', '화장실', '베란다',
};

/// 성별/인구통계 단어 (검색 키워드에서 제외)
const _demographicWords = {
  '남자', '여자', '남성', '여성', '남아', '여아', '유아', '아동',
  '키즈', '주니어', '시니어', '성인', '어린이', '베이비',
};

/// 수량 토큰 패턴 (100개, 3kg, 500ml, 6캔, 120정, 10매, 5봉, 2박스 등)
final _quantityTokenPattern = RegExp(
  r'^\d+\.?\d*(개|kg|g|mg|ml|l|L|리터|캔|병|팩|포|입|매|봉|박스|세트|정|캡슐|알|환|구|롤|장|묶음|ea|EA)$',
);

/// 스펙/컬러 패턴
final _specPattern = RegExp(
  r'\b\d+[GT]B\b|\b\d+[GT]b\b|'
  r'\b\d+mm\b|\b\d+인치\b|\b\d+cm\b|'
  r'[A-Z]{2,}\d{3,}[-/][A-Z0-9]+|'
  r'\b[A-Z]{2}\d{4,}\b',
  caseSensitive: false,
);

const _colorWords = {
  '블랙', '화이트', '그레이', '실버', '골드', '핑크', '블루', '레드',
  '그린', '퍼플', '옐로우', '네이비', '베이지', '브라운', '오렌지',
  'black', 'white', 'gray', 'silver', 'gold', 'pink', 'blue', 'red',
  'green', 'purple', 'yellow', 'navy', 'beige', 'brown', 'orange',
  '스타라이트', '미드나이트', '스페이스그레이', '시에라블루',
  '그래파이트', '딥퍼플', '팬텀블랙', '크림', '라벤더',
};

/// 토큰이 필터 대상인지 확인
bool _isFilteredToken(String token) {
  if (_noiseWords.contains(token)) return true;
  if (_descriptorWords.contains(token)) return true;
  if (_usageContextWords.contains(token)) return true;
  if (_demographicWords.contains(token)) return true;
  if (_colorWords.contains(token.toLowerCase())) return true;
  if (_quantityTokenPattern.hasMatch(token)) return true;
  // 단순 숫자만 있는 토큰 (예: "5.3", "100")
  if (RegExp(r'^[\d.]+$').hasMatch(token)) return true;
  // 1글자 비한글 토큰
  if (token.length <= 1 && !RegExp(r'[가-힣]').hasMatch(token)) return true;
  return false;
}

/// 카테고리에서 앵커 토큰 추출 (category3 우선)
List<String> _getAnchorTokens(Product product) {
  final anchors = <String>[];

  for (final cat in [product.category3, product.category2]) {
    if (cat == null || cat.isEmpty) continue;
    for (final part in cat.split('/')) {
      final trimmed = part.trim();
      if (trimmed.isNotEmpty) anchors.add(trimmed);
    }
  }

  return anchors;
}

/// 제목 토큰에서 첫 번째 연속 핵심 토큰 그룹을 추출 (폴백용)
List<String> _extractProductNameTokens(List<String> allTokens) {
  final group = <String>[];
  bool started = false;

  for (final token in allTokens) {
    if (_isFilteredToken(token)) {
      if (started) break;
      continue;
    }
    started = true;
    group.add(token);
  }

  return group;
}

/// 상품 제목에서 검색 키워드 후보 1~3개 추출 (로컬 폴백)
///
/// Gemini 키워드가 없는 경우(기존 상품, Naver API 직접 검색 결과)를 위한 폴백.
/// category3 토큰을 앵커로 사용하여 앵커 앞 수식어 + 앵커로 키워드를 구성.
/// 앵커가 없으면 기존 연속 그룹 방식으로 폴백.
List<String> extractKeywords(Product product) {
  var title = product.title;
  final brand = product.brand ?? '';
  final maker = product.maker ?? '';

  // 1. brand/maker 제거 (상품명 추출용 — 나중에 브랜드는 별도로 붙임)
  if (brand.isNotEmpty) {
    title = title.replaceAll(brand, '');
  }
  if (maker.isNotEmpty && maker != brand) {
    title = title.replaceAll(maker, '');
  }

  // 2. 괄호 내용 제거
  title = title.replaceAll(RegExp(r'\[[^\]]*\]'), '');
  title = title.replaceAll(RegExp(r'\([^)]*\)'), '');
  title = title.replaceAll(RegExp(r'\{[^}]*\}'), '');

  // 3. HTML entities 제거
  title = title.replaceAll(RegExp(r'&[a-zA-Z]+;'), '');

  // 4. 스펙 패턴 제거
  title = title.replaceAll(_specPattern, '');

  // 5. 토큰 분리
  final allTokens = title
      .split(RegExp(r'[\s/·,+]+'))
      .where((t) => t.isNotEmpty)
      .toList();

  // 브랜드 결정 (brand 우선, 없으면 maker)
  final effectiveBrand = brand.isNotEmpty ? brand : maker;

  // 6. 카테고리 앵커 방식
  final anchors = _getAnchorTokens(product);
  if (anchors.isNotEmpty) {
    return _buildAnchorKeywords(allTokens, anchors, effectiveBrand);
  }

  // 7. 앵커 없으면 기존 연속 그룹 방식
  return _buildGroupKeywords(allTokens, effectiveBrand, product);
}

/// 앵커 기반 키워드 생성
List<String> _buildAnchorKeywords(
  List<String> allTokens,
  List<String> anchors,
  String effectiveBrand,
) {
  // 제목에서 앵커 토큰을 찾고, 그 앞의 수식어를 포함
  final candidates = <String>[];

  for (final anchor in anchors) {
    // 앵커가 토큰에 포함되는 위치 찾기
    final anchorIdx = allTokens.indexWhere(
      (t) => t.contains(anchor) || anchor.contains(t),
    );

    if (anchorIdx == -1) continue;

    // 앵커 토큰 (실제 제목에 나온 형태 사용)
    final anchorToken = allTokens[anchorIdx];

    // 앵커 바로 앞의 비필터 토큰들을 수식어로 수집 (최대 2개)
    final modifiers = <String>[];
    for (int i = anchorIdx - 1; i >= 0 && modifiers.length < 2; i--) {
      final t = allTokens[i];
      if (_isFilteredToken(t)) break;
      modifiers.insert(0, t);
    }

    // 후보1: 수식어 + 앵커 (예: "긴팔 티셔츠")
    if (modifiers.isNotEmpty) {
      final full = [...modifiers, anchorToken].join(' ');
      if (!candidates.contains(full)) candidates.add(full);
    }

    // 후보2: 앵커만 (예: "티셔츠")
    if (!candidates.contains(anchorToken)) candidates.add(anchorToken);

    if (candidates.length >= 3) break;
  }

  if (candidates.isEmpty) {
    // 앵커를 제목에서 못 찾으면 첫 번째 앵커를 그냥 사용
    candidates.add(anchors.first);
  }

  // 브랜드 + 첫 번째 키워드를 맨 앞에 추가
  if (effectiveBrand.isNotEmpty && candidates.isNotEmpty) {
    final branded = '$effectiveBrand ${candidates.first}';
    if (!candidates.contains(branded)) {
      candidates.insert(0, branded);
    }
  }

  return candidates.take(3).toList();
}

/// 연속 그룹 방식 키워드 생성 (앵커 없을 때 폴백)
List<String> _buildGroupKeywords(
  List<String> allTokens,
  String effectiveBrand,
  Product product,
) {
  final productName = _extractProductNameTokens(allTokens);

  if (productName.isEmpty) {
    if (effectiveBrand.isNotEmpty) {
      return [effectiveBrand];
    }
    final fallback = product.title.split(RegExp(r'\s+')).take(2).join(' ');
    return [fallback];
  }

  final candidates = <String>[];

  // 후보1: "브랜드 상품명" (최대 브랜드 + 3토큰)
  if (effectiveBrand.isNotEmpty) {
    final nameForBrand = productName.take(3).join(' ');
    candidates.add('$effectiveBrand $nameForBrand');
  }

  // 후보2~: 상품명만 (길이별)
  if (productName.length >= 3) {
    final c = productName.take(3).join(' ');
    if (!candidates.contains(c)) candidates.add(c);
  }

  if (productName.length >= 2) {
    final c = productName.take(2).join(' ');
    if (!candidates.contains(c)) candidates.add(c);
  }

  // 가장 짧은: 토큰 1개
  final c1 = productName.first;
  if (!candidates.contains(c1)) candidates.add(c1);

  return candidates.take(3).toList();
}
