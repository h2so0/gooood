import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/product.dart';

class DealBadgeWidget extends ConsumerWidget {
  final DealBadge badge;
  const DealBadgeWidget({super.key, required this.badge});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = _badgeColors();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        badge.shortLabel,
        style: TextStyle(
          color: colors.$2,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  (Color bg, Color text) _badgeColors() {
    switch (badge) {
      case DealBadge.todayDeal:
      case DealBadge.best100:
      case DealBadge.shoppingLive:
      case DealBadge.naverPromo:
        return (const Color(0xFF5A8C5A), Colors.white);
      case DealBadge.st11:
        return (const Color(0xFF9E5B5F), Colors.white);
      case DealBadge.gmarket:
        return (const Color(0xFF5B7A9E), Colors.white);
      case DealBadge.auction:
        return (const Color(0xFF8C7355), Colors.white);
    }
  }
}
