enum SortOption {
  recommended('추천순'),
  dropRate('할인율순'),
  priceLow('가격 낮은순'),
  priceHigh('가격 높은순'),
  review('리뷰순');

  final String label;
  const SortOption(this.label);
}
