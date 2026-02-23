import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/product.dart';

/// 판매처별 시그니처 색상
class SourceColors {
  static const naver = Color(0xFF03C75A);
  static const st11 = Color(0xFFFF0033);
  static const gmarket = Color(0xFF00A650);
  static const auction = Color(0xFFE60033);
  static const lotteon = Color(0xFFE50011);
  static const ssg = Color(0xFFF2A900);

  static Color forBadge(DealBadge badge) {
    switch (badge) {
      case DealBadge.todayDeal:
      case DealBadge.best100:
      case DealBadge.shoppingLive:
      case DealBadge.naverPromo:
        return naver;
      case DealBadge.st11:
        return st11;
      case DealBadge.gmarket:
        return gmarket;
      case DealBadge.auction:
        return auction;
      case DealBadge.lotteon:
        return lotteon;
      case DealBadge.ssg:
        return ssg;
    }
  }
}

class DealBadgeWidget extends ConsumerWidget {
  final DealBadge badge;
  const DealBadgeWidget({super.key, required this.badge});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brandColor = SourceColors.forBadge(badge);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: brandColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        badge.shortLabel,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
