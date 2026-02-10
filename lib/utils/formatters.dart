import 'package:intl/intl.dart';

final priceFormat = NumberFormat('#,###', 'ko_KR');

String formatPrice(int price) => '${priceFormat.format(price)}원';

String formatCount(int n) {
  if (n >= 100000) return '${(n / 10000).toStringAsFixed(0)}만';
  if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}만';
  return priceFormat.format(n);
}
