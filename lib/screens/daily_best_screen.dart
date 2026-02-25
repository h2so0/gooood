import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/product.dart';
import '../providers/daily_best_provider.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/product_image.dart';
import '../widgets/coupang_banner.dart';
import '../widgets/screen_header.dart';
import 'detail/product_detail_screen.dart';

class DailyBestScreen extends ConsumerWidget {
  const DailyBestScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tteolgaThemeProvider);
    final topPadding = MediaQuery.of(context).padding.top;
    final bestAsync = ref.watch(dailyBestProvider);

    return Scaffold(
      backgroundColor: t.bg,
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, topPadding + 8, 16, 40),
        children: [
          ScreenHeader(theme: t, title: '오늘의 BEST'),
          const SizedBox(height: 12),
          // 날짜 표시
          Center(
            child: Text(
              _todayLabel(),
              style: TextStyle(color: t.textTertiary, fontSize: 13),
            ),
          ),
          const SizedBox(height: 20),
          bestAsync.when(
            data: (products) {
              if (products.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 60),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.emoji_events_outlined,
                            color: t.textTertiary, size: 48),
                        const SizedBox(height: 12),
                        Text('아직 오늘의 BEST가 선정되지 않았습니다',
                            style: TextStyle(
                                color: t.textTertiary, fontSize: 14)),
                      ],
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  ...List.generate(products.length, (i) {
                    return _DailyBestCard(
                      rank: i + 1,
                      product: products[i],
                      theme: t,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              ProductDetailScreen(product: products[i]),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                  CoupangBanner(),
                ],
              );
            },
            loading: () => Padding(
              padding: const EdgeInsets.symmetric(vertical: 60),
              child: Center(
                  child: CircularProgressIndicator(color: t.textTertiary)),
            ),
            error: (_, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 60),
              child: Center(
                child: Text('데이터를 불러올 수 없습니다',
                    style: TextStyle(color: t.textTertiary, fontSize: 14)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _todayLabel() {
    final now = DateTime.now();
    return '${now.year}년 ${now.month}월 ${now.day}일 선정';
  }
}

class _DailyBestCard extends StatelessWidget {
  final int rank;
  final Product product;
  final TteolgaTheme theme;
  final VoidCallback onTap;

  const _DailyBestCard({
    required this.rank,
    required this.product,
    required this.theme,
    required this.onTap,
  });

  Color get _rankColor {
    switch (rank) {
      case 1:
        return const Color(0xFFFFD700); // 금
      case 2:
        return const Color(0xFFC0C0C0); // 은
      case 3:
        return const Color(0xFFCD7F32); // 동
      default:
        return theme.textTertiary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final drop = product.dropRate;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.border, width: 0.5),
        ),
        child: Row(
          children: [
            // 순위
            SizedBox(
              width: 32,
              child: Text(
                '$rank',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _rankColor,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // 이미지
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 80,
                height: 80,
                child: ProductImage(
                  imageUrl: product.imageUrl,
                  fit: BoxFit.cover,
                  errorIcon: Icons.shopping_bag_outlined,
                  errorIconSize: 24,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // 상품 정보
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 14,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        product.displayMallName,
                        style: TextStyle(color: t.textTertiary, fontSize: 12),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: t.textTertiary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${calcBestScore(product).toStringAsFixed(1)}점',
                          style: TextStyle(
                            color: t.textTertiary,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        formatPrice(product.currentPrice),
                        style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (drop > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: t.drop.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${drop.round()}%',
                            style: TextStyle(
                              color: t.drop,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
