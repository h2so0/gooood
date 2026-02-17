class KeywordWishItem {
  final String keyword;
  final DateTime createdAt;
  final int? targetPrice;
  final String? category;

  KeywordWishItem({
    required this.keyword,
    required this.createdAt,
    this.targetPrice,
    this.category,
  });

  Map<String, dynamic> toJson() => {
        'keyword': keyword,
        'createdAt': createdAt.toIso8601String(),
        'targetPrice': targetPrice,
        'category': category,
      };

  factory KeywordWishItem.fromJson(Map<String, dynamic> json) =>
      KeywordWishItem(
        keyword: json['keyword'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        targetPrice: (json['targetPrice'] as num?)?.toInt(),
        category: json['category'] as String?,
      );

  KeywordWishItem copyWith({
    String? keyword,
    DateTime? createdAt,
    int? targetPrice,
    String? category,
    bool clearTargetPrice = false,
  }) {
    return KeywordWishItem(
      keyword: keyword ?? this.keyword,
      createdAt: createdAt ?? this.createdAt,
      targetPrice: clearTargetPrice ? null : (targetPrice ?? this.targetPrice),
      category: category ?? this.category,
    );
  }
}
