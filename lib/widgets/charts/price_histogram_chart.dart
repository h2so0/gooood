import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../models/keyword_price_data.dart';
import '../../theme/app_theme.dart';

class PriceHistogramChart extends StatefulWidget {
  final List<PriceBucket> buckets;
  final TteolgaTheme theme;

  const PriceHistogramChart({
    super.key,
    required this.buckets,
    required this.theme,
  });

  @override
  State<PriceHistogramChart> createState() => _PriceHistogramChartState();
}

class _PriceHistogramChartState extends State<PriceHistogramChart> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    if (widget.buckets.isEmpty) return const SizedBox.shrink();

    final maxCount =
        widget.buckets.map((b) => b.count).reduce((a, b) => a > b ? a : b);

    // 바 폭: 화면 기반 자동 계산
    final screenWidth = MediaQuery.of(context).size.width;
    final availableWidth = screenWidth - 64; // 좌우 패딩
    final barWidth = (availableWidth / widget.buckets.length * 0.6)
        .clamp(12.0, 32.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('가격 분포',
            style: TextStyle(
                color: t.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 12),
        SizedBox(
          height: 150,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxCount.toDouble() * 1.3,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  tooltipRoundedRadius: 10,
                  tooltipPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  getTooltipColor: (_) => t.card,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final bucket = widget.buckets[group.x.toInt()];
                    return BarTooltipItem(
                      '${bucket.label}\n${bucket.count}개',
                      TextStyle(
                        color: t.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  },
                ),
                touchCallback: (event, response) {
                  setState(() {
                    if (response == null || response.spot == null) {
                      _touchedIndex = -1;
                    } else {
                      _touchedIndex = response.spot!.touchedBarGroupIndex;
                    }
                  });
                },
              ),
              titlesData: FlTitlesData(
                show: true,
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= widget.buckets.length) {
                        return const SizedBox.shrink();
                      }
                      if (widget.buckets.length > 5 && idx % 2 != 0) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _shortLabel(widget.buckets[idx]),
                          style:
                              TextStyle(color: t.textTertiary, fontSize: 10),
                        ),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              gridData: const FlGridData(show: false),
              barGroups: widget.buckets.asMap().entries.map((entry) {
                final isTouched = entry.key == _touchedIndex;
                return BarChartGroupData(
                  x: entry.key,
                  barRods: [
                    BarChartRodData(
                      toY: entry.value.count.toDouble(),
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: isTouched
                            ? [
                                t.textSecondary.withValues(alpha: 0.6),
                                t.textSecondary,
                              ]
                            : [
                                t.textSecondary.withValues(alpha: 0.3),
                                t.textSecondary.withValues(alpha: 0.8),
                              ],
                      ),
                      width: barWidth,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6)),
                    ),
                  ],
                  showingTooltipIndicators: isTouched ? [0] : [],
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  String _shortLabel(PriceBucket bucket) {
    if (bucket.rangeStart >= 10000) {
      final man = bucket.rangeStart / 10000;
      if (man == man.roundToDouble()) return '${man.toInt()}만';
      return '${man.toStringAsFixed(1)}만';
    }
    return '${(bucket.rangeStart / 1000).toStringAsFixed(0)}천';
  }
}
