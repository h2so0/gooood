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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: t.textPrimary,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        badge.shortLabel,
        style: TextStyle(
          color: t.bg,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
