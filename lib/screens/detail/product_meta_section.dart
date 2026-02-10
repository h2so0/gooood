import 'package:flutter/material.dart';
import '../../models/product.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';

class ReviewRow extends StatelessWidget {
  final Product product;
  final TteolgaTheme theme;
  const ReviewRow({super.key, required this.product, required this.theme});

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final p = product;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.border, width: 0.5),
      ),
      child: Row(
        children: [
          if (p.reviewScore != null) ...[
            _starIcon(t, p.reviewScore!),
            const SizedBox(width: 5),
            Text(
              p.reviewScore!.toStringAsFixed(1),
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (p.reviewCount != null) ...[
            if (p.reviewScore != null) const SizedBox(width: 2),
            Text(
              p.reviewScore != null
                  ? ' (${formatCount(p.reviewCount!)})'
                  : '리뷰 ${formatCount(p.reviewCount!)}개',
              style: TextStyle(color: t.textTertiary, fontSize: 13),
            ),
          ],
          const Spacer(),
          if (p.purchaseCount != null)
            Text(
              '${formatCount(p.purchaseCount!)}명 구매',
              style: TextStyle(color: t.textSecondary, fontSize: 13),
            ),
        ],
      ),
    );
  }

  Widget _starIcon(TteolgaTheme t, double score) {
    if (score >= 4.5) return Icon(Icons.star, size: 18, color: t.star);
    if (score >= 3.5) {
      return Icon(Icons.star_half, size: 18, color: t.star);
    }
    return Icon(Icons.star_border, size: 18, color: t.star);
  }
}

class DeliveryRow extends StatelessWidget {
  final Product product;
  final TteolgaTheme theme;
  const DeliveryRow({super.key, required this.product, required this.theme});

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final items = <String>[];
    if (product.isDeliveryFree) items.add('무료배송');
    if (product.isArrivalGuarantee) items.add('도착보장');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.border, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(Icons.local_shipping_outlined,
              size: 16, color: t.textSecondary),
          const SizedBox(width: 8),
          Text(
            items.join('  ·  '),
            style: TextStyle(color: t.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class CountdownRow extends StatelessWidget {
  final Duration remaining;
  final TteolgaTheme theme;
  const CountdownRow(
      {super.key, required this.remaining, required this.theme});

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final hours = remaining.inHours;
    final mins = remaining.inMinutes % 60;
    final secs = remaining.inSeconds % 60;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: t.drop.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, size: 16, color: t.drop),
          const SizedBox(width: 8),
          Text(
            '특가 종료까지',
            style: TextStyle(color: t.textSecondary, fontSize: 14),
          ),
          const Spacer(),
          _timeBlock(t, hours),
          _timeSep(t),
          _timeBlock(t, mins),
          _timeSep(t),
          _timeBlock(t, secs),
        ],
      ),
    );
  }

  Widget _timeBlock(TteolgaTheme t, int value) {
    return Container(
      width: 32,
      height: 28,
      decoration: BoxDecoration(
        color: t.drop.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        value.toString().padLeft(2, '0'),
        style: TextStyle(
          color: t.drop,
          fontSize: 15,
          fontWeight: FontWeight.w800,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  Widget _timeSep(TteolgaTheme t) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Text(
        ':',
        style: TextStyle(
          color: t.drop.withValues(alpha: 0.5),
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class CtaButton extends StatelessWidget {
  final Product product;
  final TteolgaTheme theme;
  final double bottomPadding;
  final VoidCallback onTap;
  const CtaButton({
    super.key,
    required this.product,
    required this.theme,
    required this.bottomPadding,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding + 16),
      decoration: BoxDecoration(
        color: t.bg,
        border: Border(top: BorderSide(color: t.border, width: 0.5)),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: t.drop,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: Text(
              product.dropRate > 0
                  ? '${formatPrice(product.currentPrice)} 구매하기'
                  : '구매하기',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
