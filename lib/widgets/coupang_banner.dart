import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/url_launcher_helper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 쿠팡 파트너스 배너 (홈 피드 삽입용, 슬림 스타일)
class CoupangBanner extends ConsumerWidget {
  const CoupangBanner({super.key});

  static const _coupangUrl = 'https://link.coupang.com/a/dJQwlK';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tteolgaThemeProvider);

    return GestureDetector(
      onTap: _openCoupang,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.border, width: 0.5),
        ),
        child: Row(
          children: [
            // 쿠팡 로고 심볼
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFFE64B3C),
                borderRadius: BorderRadius.circular(7),
              ),
              alignment: Alignment.center,
              child: const Text(
                'C',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '쿠팡 골드박스 특가',
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '파트너스 활동으로 수수료를 제공받습니다',
                    style: TextStyle(
                      color: t.textTertiary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: t.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCoupang() => launchProductUrl(_coupangUrl);
}

/// 메이슨리 그리드 안에 삽입되는 세로형 배너 카드
class CoupangBannerCard extends ConsumerWidget {
  const CoupangBannerCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tteolgaThemeProvider);

    return GestureDetector(
      onTap: () => launchProductUrl(CoupangBanner._coupangUrl),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFFE64B3C),
                borderRadius: BorderRadius.circular(7),
              ),
              alignment: Alignment.center,
              child: const Text(
                'C',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '쿠팡 골드박스\n특가',
              style: TextStyle(
                color: t.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  '바로가기',
                  style: TextStyle(
                    color: t.textTertiary,
                    fontSize: 11,
                  ),
                ),
                Icon(Icons.chevron_right, color: t.textTertiary, size: 14),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '파트너스 활동으로\n수수료를 제공받습니다',
              style: TextStyle(
                color: t.textTertiary,
                fontSize: 9,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 상품 리스트에 배너를 섞어서 보여주기 위한 인덱스 매핑 헬퍼
class BannerMixer {
  BannerMixer._();

  static const interval = 20;

  /// 배너 포함 전체 아이템 수
  static int itemCount(int productCount) {
    return productCount + _bannerCount(productCount);
  }

  static int _bannerCount(int productCount) {
    if (productCount <= interval) return 0;
    return (productCount - 1) ~/ interval;
  }

  /// 해당 인덱스가 배너인지 여부
  static bool isBanner(int visualIndex) {
    if (visualIndex < interval) return false;
    return (visualIndex - interval) % (interval + 1) == 0;
  }

  /// 배너가 아닌 경우 실제 상품 인덱스
  static int productIndex(int visualIndex) {
    if (visualIndex < interval) return visualIndex;
    final adjusted = visualIndex - interval;
    final group = adjusted ~/ (interval + 1);
    final posInGroup = adjusted % (interval + 1);
    return interval + group * interval + (posInGroup - 1);
  }
}
