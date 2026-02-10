import 'package:flutter/material.dart';
import '../../models/product.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/product_image.dart';
import '../product_detail_screen.dart';

class ViewedProductsSheet extends StatelessWidget {
  final List<Product> products;
  final TteolgaTheme theme;
  const ViewedProductsSheet(
      {super.key, required this.products, required this.theme});

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final t = theme;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: t.textTertiary.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              )),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Text('내가 본 상품',
                  style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Text('${products.length}',
                  style:
                      TextStyle(color: t.textTertiary, fontSize: 14)),
            ]),
          ),
          const SizedBox(height: 12),
          Container(height: 0.5, color: t.border),
          if (products.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 60),
              child: Text('아직 본 상품이 없어요',
                  style:
                      TextStyle(color: t.textTertiary, fontSize: 14)),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                    16, 8, 16, bottomPadding + 16),
                itemCount: products.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: 0),
                itemBuilder: (context, i) => ViewedProductTile(
                    product: products[i], theme: t),
              ),
            ),
        ],
      ),
    );
  }
}

class ViewedProductTile extends StatelessWidget {
  final Product product;
  final TteolgaTheme theme;
  const ViewedProductTile(
      {super.key, required this.product, required this.theme});

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final p = product;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Navigator.of(context).pop();
        Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => ProductDetailScreen(product: p)),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 56,
                height: 56,
                child: ProductImage(
                  imageUrl: p.imageUrl,
                  fit: BoxFit.cover,
                  errorIcon: Icons.shopping_bag_outlined,
                  errorIconSize: 20,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 14,
                        height: 1.3)),
                const SizedBox(height: 4),
                Row(children: [
                  if (p.dropRate > 0) ...[
                    Text('${p.dropRate.toStringAsFixed(0)}%',
                        style: TextStyle(
                            color: t.drop,
                            fontSize: 14,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(width: 6),
                  ],
                  Text(formatPrice(p.currentPrice),
                      style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ]),
              ],
            )),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: t.textTertiary, size: 18),
          ],
        ),
      ),
    );
  }
}
