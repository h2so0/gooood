import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/product.dart';
import '../theme/app_theme.dart';

class DealBadgeWidget extends ConsumerWidget {
  final DealBadge badge;
  const DealBadgeWidget({super.key, required this.badge});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tteolgaThemeProvider);
    final colors = _badgeColors(t);

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

  (Color bg, Color text) _badgeColors(TteolgaTheme t) {
    switch (badge) {
      case DealBadge.todayDeal:
        return (const Color(0xFFFF3B30), Colors.white);
      case DealBadge.best100:
        return (const Color(0xFF007AFF), Colors.white);
      case DealBadge.shoppingLive:
        return (const Color(0xFF00C853), Colors.white);
      case DealBadge.naverPromo:
        return (const Color(0xFF8E24AA), Colors.white);
      case DealBadge.st11:
        return (const Color(0xFFFF0038), Colors.white);
      case DealBadge.gmarket:
        return (const Color(0xFF00A650), Colors.white);
      case DealBadge.auction:
        return (const Color(0xFFE53238), Colors.white);
    }
  }
}
