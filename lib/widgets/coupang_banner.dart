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
