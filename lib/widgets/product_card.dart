import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/product.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'product_image.dart';

/// 그리드형 상품 카드 (카테고리/검색 결과용)
class ProductGridCard extends ConsumerWidget {
  final Product product;
  final VoidCallback? onTap;

  const ProductGridCard({super.key, required this.product, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tteolgaThemeProvider);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 이미지 + 카운트다운
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16)),
              child: AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ProductImage(
                      imageUrl: product.imageUrl,
                      fit: BoxFit.cover,
                      errorIcon: Icons.shopping_bag_outlined,
                      errorIconSize: 28,
                    ),
                    if (product.saleEndDate != null)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: _CountdownBadge(
                            saleEndDate: product.saleEndDate!),
                      ),
                  ],
                ),
              ),
            ),
            // 상점명
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (product.displayMallName.isNotEmpty)
                    Text(
                      product.displayMallName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: t.textTertiary, fontSize: 11),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    product.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.textSecondary,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (product.dropRate > 0) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: t.drop,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '-${product.dropRate.toStringAsFixed(0)}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          formatPrice(product.currentPrice),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 실시간 카운트다운 뱃지 (30일 이내만 표시)
class _CountdownBadge extends StatefulWidget {
  final String saleEndDate;
  const _CountdownBadge({required this.saleEndDate});

  @override
  State<_CountdownBadge> createState() => _CountdownBadgeState();
}

class _CountdownBadgeState extends State<_CountdownBadge> {
  Timer? _timer;
  Duration _remaining = Duration.zero;
  DateTime? _endTime;

  @override
  void initState() {
    super.initState();
    _endTime = DateTime.tryParse(widget.saleEndDate);
    _updateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateRemaining();
    });
  }

  void _updateRemaining() {
    if (_endTime == null) return;
    final diff = _endTime!.difference(DateTime.now());
    if (mounted) setState(() => _remaining = diff);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_endTime == null) return const SizedBox.shrink();
    if (_remaining.isNegative || _remaining.inDays > 30) {
      return const SizedBox.shrink();
    }

    final String text;
    if (_remaining.inDays > 0) {
      final h = _remaining.inHours % 24;
      final m = _remaining.inMinutes % 60;
      text = '${_remaining.inDays}일 ${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    } else {
      final h = _remaining.inHours;
      final m = _remaining.inMinutes % 60;
      final s = _remaining.inSeconds % 60;
      text = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.access_time, color: Colors.white, size: 11),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
