import '../models/product.dart';

/// 노이즈 단어 (필터링 대상)
const _noiseWords = {
  '정품', '새상품', '무료배송', '특가', '할인', '자급제', '공식', '인증',
  '빠른배송', '즉시발송', '사은품', '국내정발', '당일출고', '공식판매',
  '추가금없음', '관부가세포함', '무관부가세', '국내배송', '해외직구',
  '병행수입', '한국판', '글로벌', '국내', '해외', '예약', '예약판매',
  '신품', '미개봉', '미개봉정품', '공식정품', '단독특가', '긴급', '한정',
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

/// 상품 제목에서 검색 키워드 후보 1~3개 추출
///
/// "Apple 에어팟 프로 2세대 MagSafe 충전케이스 [정품]"
///   → ["에어팟 프로 2세대", "에어팟 프로", "에어팟"]
///
/// "삼성전자 갤럭시 S24 울트라 256GB 자급제"
///   → ["갤럭시 S24 울트라", "갤럭시 S24", "갤럭시"]
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

  // 5. 토큰 분리 및 필터링
  final tokens = title
      .split(RegExp(r'[\s/·,+]+'))
      .where((t) => t.isNotEmpty)
      .where((t) => !_noiseWords.contains(t))
      .where((t) => !_colorWords.contains(t.toLowerCase()))
      .where((t) => t.length > 1 || RegExp(r'[가-힣]').hasMatch(t))
      // 단순 숫자만 있는 토큰 제거
      .where((t) => !RegExp(r'^\d+$').hasMatch(t))
      .toList();

  if (tokens.isEmpty) {
    // 폴백: 원래 제목에서 첫 몇 단어
    final fallback = product.title.split(RegExp(r'\s+')).take(2).join(' ');
    return [fallback];
  }

  // 6. 후보 생성 (구체적 → 광범위)
  final candidates = <String>[];

  if (tokens.length >= 3) {
    // 후보1: 핵심 토큰 3~4개
    final count1 = tokens.length >= 4 ? 4 : 3;
    candidates.add(tokens.take(count1).join(' '));
  }

  if (tokens.length >= 2) {
    // 후보2: 핵심 토큰 2~3개
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
    // 후보3: 핵심 토큰 1~2개
    final c3 = tokens.length >= 2
        ? tokens.take(2).join(' ')
        : tokens.first;
    if (!candidates.contains(c3)) candidates.add(c3);

    // 가장 광범위: 1개
    if (tokens.length >= 2 && !candidates.contains(tokens.first)) {
      candidates.add(tokens.first);
    }
  }

  // 7. 최대 3개, 중복 제거
  return candidates.take(3).toList();
}
