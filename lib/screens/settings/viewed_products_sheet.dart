import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/viewed_products_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/product_image.dart';
import '../product_detail_screen.dart';

class ViewedProductsSheet extends ConsumerWidget {
  const ViewedProductsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(viewedProductsProvider);
    final t = ref.watch(tteolgaThemeProvider);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
            ),
          ),
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
              Text('${entries.length}',
                  style: TextStyle(color: t.textTertiary, fontSize: 14)),
              const Spacer(),
              if (entries.isNotEmpty)
                GestureDetector(
                  onTap: () =>
                      ref.read(viewedProductsProvider.notifier).clearAll(),
                  child: Text('전체삭제',
                      style: TextStyle(color: t.textTertiary, fontSize: 13)),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          Container(height: 0.5, color: t.border),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 60),
              child: Text('아직 본 상품이 없어요',
                  style: TextStyle(color: t.textTertiary, fontSize: 14)),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                padding:
                    EdgeInsets.fromLTRB(16, 8, 16, bottomPadding + 16),
                itemCount: entries.length,
                separatorBuilder: (_, __) => const SizedBox(height: 0),
                itemBuilder: (context, i) {
                  final entry = entries[i];
                  return _ViewedProductTile(
                    entry: entry,
                    theme: t,
                    onDelete: () => ref
                        .read(viewedProductsProvider.notifier)
                        .remove(entry.product.id),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ViewedProductTile extends StatelessWidget {
  final ViewedProductEntry entry;
  final TteolgaTheme theme;
  final VoidCallback onDelete;

  const _ViewedProductTile({
    required this.entry,
    required this.theme,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final p = entry.product;
    final expired = entry.isExpired;

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
            // 이미지 (종료 시 흑백)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 56,
                height: 56,
                child: Stack(
                  children: [
                    ColorFiltered(
                      colorFilter: expired
                          ? const ColorFilter.matrix(<double>[
                              0.2126, 0.7152, 0.0722, 0, 0,
                              0.2126, 0.7152, 0.0722, 0, 0,
                              0.2126, 0.7152, 0.0722, 0, 0,
                              0, 0, 0, 1, 0,
                            ])
                          : const ColorFilter.mode(
                              Colors.transparent, BlendMode.dst),
                      child: ProductImage(
                        imageUrl: p.imageUrl,
                        fit: BoxFit.cover,
                        errorIcon: Icons.shopping_bag_outlined,
                        errorIconSize: 20,
                      ),
                    ),
                    if (expired)
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          '종료',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            // 상품 정보
            Expanded(
              child: Opacity(
                opacity: expired ? 0.45 : 1.0,
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
                      if (p.dropRate > 0 && !expired) ...[
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
                      const SizedBox(width: 8),
                      Text(_relativeTime(entry.viewedAt),
                          style: TextStyle(
                              color: t.textTertiary, fontSize: 11)),
                    ]),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            // 삭제 버튼
            GestureDetector(
              onTap: onDelete,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(Icons.close, color: t.textTertiary, size: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inHours < 1) return '${diff.inMinutes}분 전';
    if (diff.inDays < 1) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return '${dt.month}/${dt.day}';
  }
}
