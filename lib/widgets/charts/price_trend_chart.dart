import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../models/keyword_price_data.dart';
import '../../theme/app_theme.dart';

class PriceTrendChart extends StatelessWidget {
  final List<KeywordPriceSummary> history;
  final TteolgaTheme theme;

  const PriceTrendChart({
    super.key,
    required this.history,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final t = theme;
    if (history.length < 2) return const SizedBox.shrink();

    final minSpots = <FlSpot>[];
    final medianSpots = <FlSpot>[];
    final maxSpots = <FlSpot>[];

    for (int i = 0; i < history.length; i++) {
      final s = history[i];
      minSpots.add(FlSpot(i.toDouble(), s.minPrice.toDouble()));
      medianSpots.add(FlSpot(i.toDouble(), s.medianPrice.toDouble()));
      maxSpots.add(FlSpot(i.toDouble(), s.maxPrice.toDouble()));
    }

    final allPrices = history
        .expand((s) => [s.minPrice, s.maxPrice])
        .toList();
    final globalMin = allPrices.reduce((a, b) => a < b ? a : b).toDouble();
    final globalMax = allPrices.reduce((a, b) => a > b ? a : b).toDouble();
    final padding = (globalMax - globalMin) * 0.1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 헤더 + 인라인 칩 범례
        Row(
          children: [
            Text('가격 추이',
                style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
            const Spacer(),
            _legendChip(t, t.textPrimary, '최저'),
            const SizedBox(width: 6),
            _legendChip(t, t.textSecondary, '중간'),
            const SizedBox(width: 6),
            _legendChip(t, t.textTertiary, '최고'),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 140,
          child: LineChart(
            LineChartData(
              minY: (globalMin - padding).clamp(0, double.infinity),
              maxY: globalMax + padding,
              clipData: const FlClipData.all(),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  tooltipRoundedRadius: 10,
                  tooltipPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  getTooltipColor: (_) => t.card,
                  getTooltipItems: (spots) {
                    return spots.map((spot) {
                      final price = spot.y.toInt();
                      final label = switch (spot.barIndex) {
                        0 => '최저',
                        1 => '중간',
                        _ => '최고',
                      };
                      return LineTooltipItem(
                        '$label ${_formatManWon(price)}',
                        TextStyle(
                          color: spot.bar.color ?? t.textPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    }).toList();
                  },
                ),
              ),
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        _formatManWon(value.toInt()),
                        style: TextStyle(color: t.textTertiary, fontSize: 10),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: _xInterval(history.length),
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= history.length) {
                        return const SizedBox.shrink();
                      }
                      final date = history[idx].date;
                      final parts = date.split('-');
                      final label =
                          '${int.parse(parts[1])}/${int.parse(parts[2])}';
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(label,
                            style: TextStyle(
                                color: t.textTertiary, fontSize: 10)),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: t.border.withValues(alpha: 0.2),
                  strokeWidth: 0.5,
                ),
              ),
              lineBarsData: [
                // 최저가 (실선, gradient fill 강화)
                LineChartBarData(
                  spots: minSpots,
                  isCurved: true,
                  color: t.textPrimary,
                  barWidth: 2.5,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        t.textPrimary.withValues(alpha: 0.15),
                        t.textPrimary.withValues(alpha: 0.02),
                      ],
                    ),
                  ),
                ),
                // 중간가 (subtle)
                LineChartBarData(
                  spots: medianSpots,
                  isCurved: true,
                  color: t.textPrimary.withValues(alpha: 0.3),
                  barWidth: 1.5,
                  dotData: const FlDotData(show: false),
                ),
                // 최고가 (점선, 더 subtle)
                LineChartBarData(
                  spots: maxSpots,
                  isCurved: true,
                  color: t.textTertiary.withValues(alpha: 0.3),
                  barWidth: 1,
                  dotData: const FlDotData(show: false),
                  dashArray: [4, 4],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 인라인 칩 범례
  Widget _legendChip(TteolgaTheme t, Color color, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 3,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  double _xInterval(int dataLength) {
    if (dataLength <= 7) return 1;
    if (dataLength <= 14) return 2;
    if (dataLength <= 30) return 7;
    return 14;
  }

  String _formatManWon(int price) {
    if (price >= 10000) {
      final man = price / 10000;
      if (man == man.roundToDouble()) return '${man.toInt()}만';
      return '${man.toStringAsFixed(1)}만';
    }
    if (price >= 1000) return '${(price / 1000).toStringAsFixed(1)}천';
    return '$price';
  }
}
