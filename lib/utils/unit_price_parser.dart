class UnitPriceInfo {
  final String unitLabel; // "100g당", "1개당", "1캔당"
  final double pricePerUnit; // 단위당 가격

  const UnitPriceInfo({required this.unitLabel, required this.pricePerUnit});
}

/// 상품 제목에서 수량/중량을 추출하고 단위가격을 계산한다.
/// 파싱 실패 시 null 반환 → UI 미표시.
UnitPriceInfo? parseUnitPrice(String title, int price) {
  if (price <= 0) return null;

  // 개수 단위 (중량보다 우선 — "350ml 6캔" → 6캔 우선)
  final countInfo = _parseCount(title, price);
  if (countInfo != null) return countInfo;

  // 중량 (g 기준)
  final weightInfo = _parseWeight(title, price);
  if (weightInfo != null) return weightInfo;

  // 용량 (ml 기준)
  final volumeInfo = _parseVolume(title, price);
  if (volumeInfo != null) return volumeInfo;

  return null;
}

// ── 개수 ──────────────────────────────────────────────

final _countPattern = RegExp(
  r'(\d+(?:\.\d+)?)\s*(개입|개|캔|정|포|매|박스|세트|팩|봉|입)',
);

UnitPriceInfo? _parseCount(String title, int price) {
  final m = _countPattern.firstMatch(title);
  if (m == null) return null;

  final qty = double.tryParse(m.group(1)!);
  if (qty == null || qty <= 0) return null;

  var unit = m.group(2)!;
  if (unit == '개입' || unit == '입') unit = '개'; // 정규화

  if (qty == 1) return null; // 1개짜리는 단위가격 무의미

  return UnitPriceInfo(
    unitLabel: '1$unit당',
    pricePerUnit: price / qty,
  );
}

// ── 중량 (g 기준) ─────────────────────────────────────

final _kgPattern = RegExp(r'(\d+(?:\.\d+)?)\s*kg', caseSensitive: false);
final _gPattern = RegExp(r'(\d+(?:\.\d+)?)\s*g(?!b)', caseSensitive: false);

UnitPriceInfo? _parseWeight(String title, int price) {
  double? grams;

  final kgMatch = _kgPattern.firstMatch(title);
  if (kgMatch != null) {
    final v = double.tryParse(kgMatch.group(1)!);
    if (v != null && v > 0) grams = v * 1000;
  }

  if (grams == null) {
    final gMatch = _gPattern.firstMatch(title);
    if (gMatch != null) {
      final v = double.tryParse(gMatch.group(1)!);
      if (v != null && v > 0) grams = v;
    }
  }

  if (grams == null) return null;

  if (grams <= 100) {
    return UnitPriceInfo(
      unitLabel: '1g당',
      pricePerUnit: price / grams,
    );
  } else if (grams <= 1000) {
    return UnitPriceInfo(
      unitLabel: '100g당',
      pricePerUnit: price / grams * 100,
    );
  } else {
    return UnitPriceInfo(
      unitLabel: '1kg당',
      pricePerUnit: price / grams * 1000,
    );
  }
}

// ── 용량 (ml 기준) ────────────────────────────────────

final _lPattern = RegExp(r'(\d+(?:\.\d+)?)\s*[lL](?![\w])');
final _mlPattern = RegExp(r'(\d+(?:\.\d+)?)\s*ml', caseSensitive: false);

UnitPriceInfo? _parseVolume(String title, int price) {
  double? ml;

  final lMatch = _lPattern.firstMatch(title);
  if (lMatch != null) {
    final v = double.tryParse(lMatch.group(1)!);
    if (v != null && v > 0) ml = v * 1000;
  }

  if (ml == null) {
    final mlMatch = _mlPattern.firstMatch(title);
    if (mlMatch != null) {
      final v = double.tryParse(mlMatch.group(1)!);
      if (v != null && v > 0) ml = v;
    }
  }

  if (ml == null) return null;

  if (ml <= 100) {
    return UnitPriceInfo(
      unitLabel: '1ml당',
      pricePerUnit: price / ml,
    );
  } else if (ml <= 1000) {
    return UnitPriceInfo(
      unitLabel: '100ml당',
      pricePerUnit: price / ml * 100,
    );
  } else {
    return UnitPriceInfo(
      unitLabel: '1L당',
      pricePerUnit: price / ml * 1000,
    );
  }
}
