import '../models/product.dart';

/// 노이즈 단어 (필터링 대상)
const _noiseWords = {
  '정품', '새상품', '무료배송', '특가', '할인', '자급제', '공식', '인증',
  '빠른배송', '즉시발송', '사은품', '국내정발', '당일출고', '공식판매',
  '추가금없음', '관부가세포함', '무관부가세', '국내배송', '해외직구',
  '병행수입', '한국판', '글로벌', '국내', '해외', '예약', '예약판매',
  '신품', '미개봉', '미개봉정품', '공식정품', '단독특가', '긴급', '한정',
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
};

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

/// 카테고리에서 토큰 추출 (슬래시로 분리, 가장 구체적인 것)
Set<String> _getCategoryTokens(Product product) {
  final tokens = <String>{};

  for (final cat in [product.category3, product.category2]) {
    if (cat == null || cat.isEmpty) continue;
    // "이어폰/헤드폰" → ["이어폰", "헤드폰"]
    for (final part in cat.split('/')) {
      final trimmed = part.trim();
      if (trimmed.isNotEmpty) tokens.add(trimmed);
    }
  }

  return tokens;
}

/// 상품 제목에서 검색 키워드 후보 1~3개 추출
///
/// 서술어·카테고리 토큰을 제거하여 **제품 정체성 토큰**만 남긴 뒤 조합.
///
/// "삼성전자 갤럭시 버즈3 프로 무선 이어폰 노이즈캔슬링 블루투스 5.3 통화"
///   → ["갤럭시 버즈3 프로", "갤럭시 버즈3", "갤럭시"]
///
/// "Apple 에어팟 프로 2세대 MagSafe 충전케이스 [정품]"
///   → ["에어팟 프로 2세대", "에어팟 프로", "에어팟"]
List<String> extractKeywords(Product product) {
  var title = product.title;

  // 1. brand 제거
  final brand = product.brand ?? '';
  if (brand.isNotEmpty) {
    title = title.replaceAll(brand, '');
  }
  // maker도 제거
  final maker = product.maker ?? '';
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

  // 5. 카테고리 토큰 수집
  final categoryTokens = _getCategoryTokens(product);

  // 6. 토큰 분리 및 필터링 → 정체성 토큰만 남김
  final tokens = title
      .split(RegExp(r'[\s/·,+]+'))
      .where((t) => t.isNotEmpty)
      .where((t) => !_noiseWords.contains(t))
      .where((t) => !_descriptorWords.contains(t))
      .where((t) => !_colorWords.contains(t.toLowerCase()))
      .where((t) => t.length > 1 || RegExp(r'[가-힣]').hasMatch(t))
      // 단순 숫자만 있는 토큰 제거 (예: "5.3", "100")
      .where((t) => !RegExp(r'^[\d.]+$').hasMatch(t))
      // 카테고리 토큰 제거 (이어폰, 노트북 등)
      .where((t) => !categoryTokens.contains(t))
      .toList();

  if (tokens.isEmpty) {
    // 폴백: 원래 제목에서 첫 몇 단어
    final fallback = product.title.split(RegExp(r'\s+')).take(2).join(' ');
    return [fallback];
  }

  // 7. 후보 생성 (구체적 → 광범위, 정체성 토큰만 사용)
  final candidates = <String>[];

  if (tokens.length >= 3) {
    // 후보1: 정체성 토큰 전체 (최대 4개)
    final count1 = tokens.length >= 4 ? 4 : 3;
    candidates.add(tokens.take(count1).join(' '));
  }

  if (tokens.length >= 2) {
    // 후보2: 앞 2~3개
    final count2 = tokens.length >= 3 ? 3 : 2;
    final c2 = tokens.take(count2).join(' ');
    if (!candidates.contains(c2)) candidates.add(c2);

    // 더 짧은 버전 (2개)
    if (count2 > 2) {
      final c2short = tokens.take(2).join(' ');
      if (!candidates.contains(c2short)) candidates.add(c2short);
    }
  }

  if (tokens.isNotEmpty) {
    // 후보3: 1~2개
    final c3 =
        tokens.length >= 2 ? tokens.take(2).join(' ') : tokens.first;
    if (!candidates.contains(c3)) candidates.add(c3);

    // 가장 광범위: 1개
    if (tokens.length >= 2 && !candidates.contains(tokens.first)) {
      candidates.add(tokens.first);
    }
  }

  // 8. 최대 3개, 중복 제거
  return candidates.take(3).toList();
}
