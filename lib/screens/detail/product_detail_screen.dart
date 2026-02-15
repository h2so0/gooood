import 'dart:async';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/product.dart';
import '../../utils/url_launcher_helper.dart';
import '../../theme/app_theme.dart';
import '../../widgets/deal_badge.dart';
import '../../providers/viewed_products_provider.dart';
import '../../utils/formatters.dart';
import 'hero_image_section.dart';
import 'product_meta_section.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  final Product product;
  const ProductDetailScreen({super.key, required this.product});

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  Product get p => widget.product;

  Timer? _countdownTimer;
  Duration? _remaining;

  @override
  void initState() {
    super.initState();
    _initCountdown();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(viewedProductsProvider.notifier).add(p);
    });
  }

  void _initCountdown() {
    if (p.saleEndDate == null) return;
    try {
      final end = DateTime.parse(p.saleEndDate!);
      final diff = end.difference(DateTime.now());
      if (diff.isNegative || diff.inDays > 7) return;
      _remaining = diff;
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          final end = DateTime.parse(p.saleEndDate!);
          _remaining = end.difference(DateTime.now());
          if (_remaining!.isNegative) {
            _remaining = null;
            _countdownTimer?.cancel();
          }
        });
      });
    } catch (e) { debugPrint('[ProductDetail] countdown init error: $e'); }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  bool get _hasMetaInfo =>
      p.reviewScore != null ||
      p.reviewCount != null ||
      p.purchaseCount != null ||
      p.isDeliveryFree ||
      p.isArrivalGuarantee ||
      p.rank != null;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tteolgaThemeProvider);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    final topPadding = MediaQuery.of(context).padding.top;
    // 헤더 높이: topPadding + 8(top) + 38(button) + 8(bottom)
    final headerHeight = topPadding + 54;

    return Scaffold(
      backgroundColor: t.bg,
      body: Stack(
        children: [
          ListView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.only(top: headerHeight),
            children: [
              HeroImageSection(
                product: p,
                theme: t,
              ),

              const SizedBox(height: 20),

              // 메인 정보 영역
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (p.badge != null) ...[
                          DealBadgeWidget(badge: p.badge!),
                          const SizedBox(width: 8),
                        ],
                        if (p.mallName.isNotEmpty)
                          Text(p.mallName,
                              style: TextStyle(
                                  color: t.textTertiary, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 10),

                    Text(
                      p.title,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),

                    if (p.previousPrice != null && p.dropRate > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          formatPrice(p.previousPrice!),
                          style: TextStyle(
                            color: t.textTertiary,
                            fontSize: 13,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        if (p.dropRate > 0) ...[
                          Text(
                            '${p.dropRate.toStringAsFixed(0)}%',
                            style: TextStyle(
                              color: t.drop,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          formatPrice(p.currentPrice),
                          style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              Container(
                height: 8,
                color: t.brightness == Brightness.dark
                    ? t.surface
                    : t.border.withValues(alpha: 0.3),
              ),

              if (_hasMetaInfo || _remaining != null) ...[
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (p.rank != null) ...[
                        RankRow(product: p, theme: t),
                        const SizedBox(height: 16),
                      ],
                      if (p.reviewScore != null ||
                          p.reviewCount != null ||
                          p.purchaseCount != null) ...[
                        ReviewRow(product: p, theme: t),
                        const SizedBox(height: 16),
                      ],
                      if (p.isDeliveryFree || p.isArrivalGuarantee) ...[
                        DeliveryRow(product: p, theme: t),
                        const SizedBox(height: 16),
                      ],
                      if (_remaining != null) ...[
                        CountdownRow(remaining: _remaining!, theme: t),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),
              ],

              SizedBox(height: 80 + bottomPadding),
            ],
          ),

          // 고정 헤더
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: DetailHeader(
              theme: t,
              onBack: () => Navigator.of(context).pop(),
              onShare: _shareProduct,
            ),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: CtaButton(
              product: p,
              theme: t,
              bottomPadding: bottomPadding,
              onTap: () => launchProductUrl(p.link),
            ),
          ),
        ],
      ),
    );
  }

  void _shareProduct() {
    final encodedId = Uri.encodeComponent(p.id);
    final deepLink = 'https://gooddeal-app.web.app/product/$encodedId';
    SharePlus.instance.share(ShareParams(text: deepLink));
  }
}
