import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/product.dart';
import '../theme/app_theme.dart';
import '../widgets/deal_badge.dart';
import '../providers/product_provider.dart';
import '../utils/image_helper.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  final Product product;
  const ProductDetailScreen({super.key, required this.product});

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  static final _fmt = NumberFormat('#,###', 'ko_KR');
  Product get p => widget.product;

  Timer? _countdownTimer;
  Duration? _remaining;

  @override
  void initState() {
    super.initState();
    _initCountdown();
    // 조회 기록 저장
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
    } catch (_) {}
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
      p.isArrivalGuarantee;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tteolgaThemeProvider);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: t.bg,
      body: Stack(
        children: [
          ListView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.zero,
            children: [
              // ── 히어로 이미지 ──
              _buildHeroImage(context, t),

              const SizedBox(height: 20),

              // ── 메인 정보 영역 ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 뱃지 + 상점명
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

                    // 상품명
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

                    // ── 가격 ──
                    // 원래가 (취소선, 위에 작게)
                    if (p.previousPrice != null && p.dropRate > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '${_fmt.format(p.previousPrice)}원',
                          style: TextStyle(
                            color: t.textTertiary,
                            fontSize: 13,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ),
                    // 할인율 + 현재가 (메인)
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
                          '${_fmt.format(p.currentPrice)}원',
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

              // ── 구분선 ──
              Container(
                height: 8,
                color: t.brightness == Brightness.dark
                    ? t.surface
                    : t.border.withValues(alpha: 0.3),
              ),

              // ── 상품 정보 카드 (리뷰 · 배송 · 타이머 통합) ──
              if (_hasMetaInfo || _remaining != null) ...[
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 리뷰 / 구매
                      if (p.reviewScore != null || p.reviewCount != null || p.purchaseCount != null) ...[
                        _buildReviewRow(t),
                        const SizedBox(height: 16),
                      ],

                      // 배송 정보
                      if (p.isDeliveryFree || p.isArrivalGuarantee) ...[
                        _buildDeliveryRow(t),
                        const SizedBox(height: 16),
                      ],

                      // 카운트다운
                      if (_remaining != null) ...[
                        _buildCountdown(t),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),
              ],

              SizedBox(height: 80 + bottomPadding),
            ],
          ),

          // ── CTA ──
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildCTA(t, bottomPadding),
          ),
        ],
      ),
    );
  }

  // ────────────────────────── Hero Image ──────────────────────────

  Widget _buildHeroImage(BuildContext context, TteolgaTheme t) {
    return Stack(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: p.imageUrl.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: proxyImage(p.imageUrl),
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: t.surface),
                  errorWidget: (_, __, ___) => Container(
                    color: t.surface,
                    child: Center(
                      child: Icon(Icons.shopping_bag_outlined,
                          color: t.textTertiary, size: 48),
                    ),
                  ),
                )
              : Container(
                  color: t.surface,
                  child: Center(
                    child: Icon(Icons.shopping_bag_outlined,
                        color: t.textTertiary, size: 48),
                  ),
                ),
        ),
        // 상단 그라데이션
        Positioned(
          top: 0, left: 0, right: 0,
          height: MediaQuery.of(context).padding.top + 56,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.45),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        // 네비 버튼
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 12, right: 12,
          child: Row(
            children: [
              _overlayButton(
                icon: Icons.arrow_back_ios_new,
                onTap: () => Navigator.of(context).pop(),
              ),
              const Spacer(),
              _overlayButton(
                icon: Icons.ios_share,
                onTap: () => _shareProduct(),
              ),
            ],
          ),
        ),
        // BEST 순위
        if (p.rank != null)
          Positioned(
            bottom: 12, right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'BEST #${p.rank}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ────────────────────── Review / Purchase Row ──────────────────────

  Widget _buildReviewRow(TteolgaTheme t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.border, width: 0.5),
      ),
      child: Row(
        children: [
          // 별점
          if (p.reviewScore != null) ...[
            _starIcon(p.reviewScore!),
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
          // 리뷰 수
          if (p.reviewCount != null) ...[
            if (p.reviewScore != null) const SizedBox(width: 2),
            Text(
              p.reviewScore != null
                  ? ' (${_fmtCount(p.reviewCount!)})'
                  : '리뷰 ${_fmtCount(p.reviewCount!)}개',
              style: TextStyle(color: t.textTertiary, fontSize: 13),
            ),
          ],
          const Spacer(),
          // 구매 수
          if (p.purchaseCount != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_fmtCount(p.purchaseCount!)}명 구매',
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _starIcon(double score) {
    final t = ref.read(tteolgaThemeProvider);
    if (score >= 4.5) return Icon(Icons.star, size: 18, color: t.star);
    if (score >= 3.5) return Icon(Icons.star_half, size: 18, color: t.star);
    return Icon(Icons.star_border, size: 18, color: t.star);
  }

  // ────────────────────── Delivery Row ──────────────────────

  Widget _buildDeliveryRow(TteolgaTheme t) {
    final items = <String>[];
    if (p.isDeliveryFree) items.add('무료배송');
    if (p.isArrivalGuarantee) items.add('도착보장');

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
            style: TextStyle(
              color: t.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // ────────────────────── Countdown ──────────────────────

  Widget _buildCountdown(TteolgaTheme t) {
    final r = _remaining!;
    final hours = r.inHours;
    final mins = r.inMinutes % 60;
    final secs = r.inSeconds % 60;

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
            style: TextStyle(
              color: t.textSecondary, fontSize: 14,
            ),
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

  // ────────────────────── CTA ──────────────────────

  Widget _buildCTA(TteolgaTheme t, double bottomPadding) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding + 16),
      decoration: BoxDecoration(
        color: t.bg,
        border: Border(top: BorderSide(color: t.border, width: 0.5)),
      ),
      child: GestureDetector(
        onTap: () async {
          if (p.link.isNotEmpty) {
            final uri = Uri.parse(p.link);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          }
        },
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: t.drop,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: Text(
              p.dropRate > 0
                  ? '${_fmt.format(p.currentPrice)}원 구매하기'
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

  // ────────────────────── Share ──────────────────────

  void _shareProduct() {
    final price = _fmt.format(p.currentPrice);
    final text = '${p.title}\n${price}원\n${p.link}';
    Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('링크가 복사되었습니다'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ────────────────────── Helpers ──────────────────────

  Widget _overlayButton(
      {required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 16, color: Colors.white),
      ),
    );
  }

  String _fmtCount(int n) {
    if (n >= 100000) return '${(n / 10000).toStringAsFixed(0)}만';
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}만';
    return _fmt.format(n);
  }
}
