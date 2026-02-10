class TrendChartPoint {
  final String period;
  final double ratio;
  const TrendChartPoint({required this.period, required this.ratio});
}

class TrendKeyword {
  final String keyword;
  final double ratio;
  /// 순위 변동: 양수=상승, 음수=하락, 0=변동없음, null=신규
  final int? rankChange;
  const TrendKeyword({
    required this.keyword,
    required this.ratio,
    this.rankChange,
  });

  factory TrendKeyword.fromJson(Map<String, dynamic> json) => TrendKeyword(
    keyword: json['keyword']?.toString() ?? '',
    ratio: (json['ratio'] as num?)?.toDouble() ?? 0,
    rankChange: (json['rankChange'] as num?)?.toInt(),
  );
}

class PopularKeyword {
  final int rank;
  final String keyword;
  final String category;
  const PopularKeyword({
    required this.rank,
    required this.keyword,
    required this.category,
  });

  factory PopularKeyword.fromJson(Map<String, dynamic> json) => PopularKeyword(
    rank: (json['rank'] as num?)?.toInt() ?? 0,
    keyword: json['keyword']?.toString() ?? '',
    category: json['category']?.toString() ?? '',
  );
}

class NaverApiException implements Exception {
  final String message;
  final int statusCode;
  NaverApiException(this.message, this.statusCode);
  @override
  String toString() => 'NaverApiException($statusCode): $message';
}
