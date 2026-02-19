import 'dart:async';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/product.dart';
import '../../utils/url_launcher_helper.dart';
import '../../utils/keyword_extractor.dart';
import '../../theme/app_theme.dart';
import '../../widgets/deal_badge.dart';
import '../../widgets/keyword_price_section.dart';
import '../../providers/viewed_products_provider.dart';
import '../../services/analytics_service.dart';
import '../../services/review_service.dart';
import '../../utils/formatters.dart';
import '../../utils/unit_price_parser.dart';
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

  late final List<String> _keywords;
  int _keywordPage = 0;
  @override
  void initState() {
    super.initState();
    _initCountdown();
    _keywords = (p.searchKeywords != null && p.searchKeywords!.isNotEmpty)
        ? p.searchKeywords!
        : extractKeywords(p);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(viewedProductsProvider.notifier).add(p);
      AnalyticsService.logProductViewed(p);
      ReviewService.recordProductView();
    });
  }

  void _initCountdown() {
    if (p.saleEndDate == null) return;
    try {
      final end = DateTime.parse(p.saleEndDate!);
      final diff = end.difference(DateTime.now());
      if (diff.isNegative || diff.inDays > 7) return;
      _remaining = diff;
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) { timer.cancel(); return; }
        setState(() {
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

  bool get _hasUnitPrice => parseUnitPrice(p.title, p.currentPrice) != null;

  bool get _hasMetaInfo =>
      _hasUnitPrice ||
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
                      if (_hasUnitPrice) ...[
                        UnitPriceRow(product: p, theme: t),
                        const SizedBox(height: 16),
                      ],
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

              // 키워드 가격 추이 섹션
              if (_keywords.isNotEmpty) ...[
                Container(
                  height: 8,
                  color: t.brightness == Brightness.dark
                      ? t.surface
                      : t.border.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 16),
                _buildKeywordPriceSection(t),
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
              onTap: () {
                AnalyticsService.logPurchaseIntent(p);
                launchProductUrl(p.link);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeywordPriceSection(TteolgaTheme t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text('가격 분석',
              style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
        ),

        // 키워드 탭 (스크롤 가능)
        if (_keywords.length > 1) ...[
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: _keywords.asMap().entries.map((entry) {
                final isSelected = entry.key == _keywordPage;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _keywordPage = entry.key),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? t.textPrimary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        border: isSelected
                            ? null
                            : Border.all(color: t.border, width: 0.5),
                      ),
                      child: Text(
                        entry.value,
                        style: TextStyle(
                          color: isSelected ? t.bg : t.textSecondary,
                          fontSize: 13,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ] else
          const SizedBox(height: 8),

        // AnimatedSwitcher로 키워드 전환
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: KeywordPriceSection(
            key: ValueKey(_keywords[_keywordPage]),
            keyword: _keywords[_keywordPage],
            originalProduct: p,
          ),
        ),
      ],
    );
  }

  void _shareProduct() {
    AnalyticsService.logProductShared(p);
    final encodedId = Uri.encodeComponent(p.id);
    final deepLink = 'https://gooddeal-app.web.app/product/$encodedId';
    SharePlus.instance.share(ShareParams(text: deepLink));
  }
}
