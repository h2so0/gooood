import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/analytics_service.dart';
import '../services/click_tracker.dart';
import '../theme/app_theme.dart';

/// 공지/이벤트 배너 다이얼로그 (프로모션 스타일)
Future<void> showAnnouncementDialog(
  BuildContext context, {
  required TteolgaTheme theme,
  required String title,
  required String body,
  String? imageUrl,
  String? ctaUrl,
  String? ctaLabel,
  String? announcementId,
}) {
  return showDialog(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          color: theme.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: theme.border, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 헤더: 이미지 또는 그래디언트 배너
                _buildHeader(theme, imageUrl),

                // 타이틀
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
                  child: Text(
                    title,
                    style: TextStyle(
                      color: theme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                ),

                // 본문
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
                  child: Text(
                    body,
                    style: TextStyle(
                      color: theme.textSecondary,
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),
                ),

                // CTA 버튼
                if (ctaUrl != null && ctaUrl.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: GestureDetector(
                      onTap: () {
                        if (announcementId != null) {
                          AnalyticsService.logAnnouncementCtaClick(announcementId);
                          ClickTracker.track('announcement_cta');
                        }
                        Navigator.of(ctx).pop();
                        launchUrl(Uri.parse(ctaUrl),
                            mode: LaunchMode.externalApplication);
                      },
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE31837), Color(0xFFFF4D6A)],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFE31837)
                                  .withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                ctaLabel ?? '바로가기',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.arrow_forward_rounded,
                                  color: Colors.white, size: 18),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            // 닫기 버튼 (우측 상단)
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () {
                  if (announcementId != null) {
                    AnalyticsService.logAnnouncementClose(announcementId);
                  }
                  Navigator.of(ctx).pop();
                },
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 헤더 빌더: 이미지가 있으면 이미지, 없으면 그래디언트 배너
Widget _buildHeader(TteolgaTheme theme, String? imageUrl) {
  if (imageUrl != null && imageUrl.isNotEmpty) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        height: 170,
        width: double.infinity,
        fit: BoxFit.cover,
        placeholder: (_, _) => Container(
          height: 170,
          color: theme.surface,
        ),
        errorWidget: (_, _, _) => _gradientBanner(),
      ),
    );
  }
  return _gradientBanner();
}

Widget _gradientBanner() {
  return ClipRRect(
    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
    child: Container(
      height: 160,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE31837), Color(0xFFFF6B4A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          // 배경 패턴 (큰 원)
          Positioned(
            right: -30,
            top: -30,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
          ),
          Positioned(
            left: -20,
            bottom: -40,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          // 아이콘 + 텍스트
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.rocket_launch_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'SPECIAL DEAL',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// 업데이트 안내 다이얼로그
Future<void> showUpdateDialog(
  BuildContext context, {
  required TteolgaTheme theme,
  required String title,
  required String body,
  required String updateUrl,
  required bool forceUpdate,
}) {
  return showDialog(
    context: context,
    barrierDismissible: !forceUpdate,
    builder: (ctx) => PopScope(
      canPop: !forceUpdate,
      child: AlertDialog(
        backgroundColor: theme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: TextStyle(
            color: theme.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          body,
          style: TextStyle(
            color: theme.textSecondary,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        actions: [
          if (!forceUpdate)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                '나중에',
                style: TextStyle(color: theme.textTertiary, fontSize: 14),
              ),
            ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              launchUrl(Uri.parse(updateUrl),
                  mode: LaunchMode.externalApplication);
            },
            child: Text(
              '업데이트',
              style: TextStyle(
                color: theme.drop,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
