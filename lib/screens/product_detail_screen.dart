import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/product.dart';
import '../theme/app_theme.dart';
import '../widgets/deal_badge.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  final Product product;
  const ProductDetailScreen({super.key, required this.product});

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  int _chartRange = 30;
  static final _fmt = NumberFormat('#,###', 'ko_KR');
  Product get p => widget.product;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tteolgaThemeProvider);
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: t.bg,
      body: Stack(
        children: [
          ListView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.only(top: topPadding),
            children: [
              // Top bar
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: t.card,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.arrow_back_ios_new,
                            size: 16, color: t.textSecondary),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: t.card,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.ios_share,
                          size: 16, color: t.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Image
              if (p.imageUrl.isNotEmpty)
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: CachedNetworkImage(
                      imageUrl: p.imageUrl,
                      height: 180,
                      width: 180,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) =>
                          const SizedBox(height: 180),
                    ),
                  ),
                ),

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (p.badge != null) ...[
                      DealBadgeWidget(badge: p.badge!),
                      const SizedBox(height: 10),
                    ],
                    Text(
                      p.title,
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                    if (p.mallName.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(p.mallName,
                          style: TextStyle(
                              color: t.textTertiary, fontSize: 13)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Price card
              _card(
                t,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('현재 최저가',
                        style: TextStyle(
                            color: t.textTertiary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text(
                      '${_fmt.format(p.currentPrice)}원',
                      style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (p.previousPrice != null && p.dropRate > 0) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            '${_fmt.format(p.previousPrice)}원',
                            style: TextStyle(
                              color: t.textTertiary,
                              fontSize: 14,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '-${_fmt.format(p.previousPrice! - p.currentPrice)}원 (-${p.dropRate.toStringAsFixed(1)}%)',
                            style: TextStyle(
                              color: t.drop,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        _stat(t, '역대 최저', p.lowestEver),
                        _stat(t, '역대 최고', p.highestEver),
                        _stat(t, '30일 평균', p.avgPrice),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Chart
              _buildChart(t),
              const SizedBox(height: 10),

              // Alert
              _card(
                t,
                child: Row(
                  children: [
                    Icon(Icons.notifications_active_outlined,
                        color: t.textSecondary, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('가격 알림',
                              style: TextStyle(
                                  color: t.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text('가격이 떨어지면 알려드립니다',
                              style: TextStyle(
                                  color: t.textTertiary, fontSize: 12)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: t.border, width: 0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('알림 설정',
                          style: TextStyle(
                              color: t.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 96 + bottomPadding),
            ],
          ),

          // CTA
          Positioned(
            left: 16,
            right: 16,
            bottom: bottomPadding + 16,
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
                  color: t.textPrimary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    '최저가로 구매하기',
                    style: TextStyle(
                      color: t.bg,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(TteolgaTheme t, {required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.border, width: 0.5),
        ),
        child: child,
      ),
    );
  }

  Widget _stat(TteolgaTheme t, String label, int? value) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: TextStyle(color: t.textTertiary, fontSize: 11)),
          const SizedBox(height: 4),
          Text(
            value != null ? '${_fmt.format(value)}원' : '-',
            style: TextStyle(
                color: t.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildChart(TteolgaTheme t) {
    final history = p.priceHistory;
    if (history.isEmpty) {
      return _card(t,
          child: SizedBox(
            height: 160,
            child: Center(
                child: Text('가격 이력이 없습니다',
                    style: TextStyle(color: t.textTertiary))),
          ));
    }

    final filtered = history
        .where((pt) => pt.date
            .isAfter(DateTime.now().subtract(Duration(days: _chartRange))))
        .toList();

    final prices = filtered.map((pt) => pt.price.toDouble()).toList();
    final minP = prices.isEmpty ? 0.0 : prices.reduce((a, b) => a < b ? a : b);
    final maxP = prices.isEmpty ? 1.0 : prices.reduce((a, b) => a > b ? a : b);
    final range = maxP - minP;

    return _card(
      t,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('가격 추이',
                  style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              _rangeBtn(t, '7일', _chartRange == 7,
                  () => setState(() => _chartRange = 7)),
              _rangeBtn(t, '30일', _chartRange == 30,
                  () => setState(() => _chartRange = 30)),
              _rangeBtn(t, '90일', _chartRange == 90,
                  () => setState(() => _chartRange = 90)),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 160,
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                minY: minP - range * 0.1,
                maxY: maxP + range * 0.1,
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) => spots
                        .map((s) => LineTooltipItem(
                              '${_fmt.format(s.y.round())}원',
                              const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600),
                            ))
                        .toList(),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: filtered
                        .asMap()
                        .entries
                        .map((e) => FlSpot(
                            e.key.toDouble(), e.value.price.toDouble()))
                        .toList(),
                    isCurved: true,
                    curveSmoothness: 0.3,
                    color: t.textPrimary,
                    barWidth: 1.5,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: t.textPrimary.withValues(alpha: 0.05),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rangeBtn(
      TteolgaTheme t, String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? t.textPrimary.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? t.textPrimary : t.textTertiary,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
