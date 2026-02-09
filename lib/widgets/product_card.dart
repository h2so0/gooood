import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../theme/app_theme.dart';
import 'deal_badge.dart';

/// 리스트형 상품 카드 (홈 피드용 - 기존 그대로)
class ProductCard extends ConsumerWidget {
  final Product product;
  final VoidCallback? onTap;

  const ProductCard({super.key, required this.product, this.onTap});

  static final _fmt = NumberFormat('#,###', 'ko_KR');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tteolgaThemeProvider);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.border, width: 0.5),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: product.imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: product.imageUrl,
                      width: 68,
                      height: 68,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _thumb(t),
                      errorWidget: (_, __, ___) => _thumb(t),
                    )
                  : _thumb(t),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (product.badge != null) ...[
                    DealBadgeWidget(badge: product.badge!),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    product.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        '${_fmt.format(product.currentPrice)}원',
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (product.dropRate > 0) ...[
                        const SizedBox(width: 8),
                        Text(
                          '-${product.dropRate.toStringAsFixed(0)}%',
                          style: TextStyle(
                            color: t.drop,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (product.mallName.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      product.mallName,
                      style:
                          TextStyle(color: t.textTertiary, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumb(TteolgaTheme t) {
    return Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(Icons.shopping_bag_outlined,
          color: t.textTertiary, size: 24),
    );
  }
}

/// 그리드형 상품 카드 (카테고리/검색 결과용)
/// 상점명(좌측) → 상품명 2줄(좌측) → 할인율(빨간박스 흰텍스트) + 금액(우측)
class ProductGridCard extends ConsumerWidget {
  final Product product;
  final VoidCallback? onTap;

  const ProductGridCard({super.key, required this.product, this.onTap});

  static final _fmt = NumberFormat('#,###', 'ko_KR');

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
            // 이미지 + 뱃지 오버레이
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16)),
              child: AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    product.imageUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: product.imageUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, __) =>
                                Container(color: t.surface),
                            errorWidget: (_, __, ___) => Container(
                              color: t.surface,
                              child: Center(
                                child: Icon(Icons.shopping_bag_outlined,
                                    color: t.textTertiary, size: 28),
                              ),
                            ),
                          )
                        : Container(
                            color: t.surface,
                            child: Center(
                              child: Icon(Icons.shopping_bag_outlined,
                                  color: t.textTertiary, size: 28),
                            ),
                          ),
                    if (product.badge != null)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: DealBadgeWidget(badge: product.badge!),
                      ),
                  ],
                ),
              ),
            ),
            // 상점명 (이미지 바로 아래, 간격 없음)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (product.mallName.isNotEmpty)
                    Text(
                      product.mallName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: t.textTertiary, fontSize: 11),
                    ),
                  const SizedBox(height: 2),
                  // 상품명 2줄 (좌측 정렬)
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
                  // 할인율(빨간박스 흰텍스트) + 금액
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
                          '${_fmt.format(product.currentPrice)}원',
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
