import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';
import '../widgets/startup_popup.dart';
import 'analytics_service.dart';
import 'click_tracker.dart';

const _keyAnnouncementShownDate = 'popup_announcement_shown_date';
const _keyUpdateDismissedVersion = 'popup_update_dismissed_version';

class StartupPopupService {
  static Future<void> checkAndShow(
      BuildContext context, WidgetRef ref) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('cache')
          .doc('startup_popup')
          .get();

      if (!doc.exists || doc.data() == null) return;
      final data = doc.data()!;

      if (!context.mounted) return;
      final theme = ref.read(tteolgaThemeProvider);

      // 우선순위: 업데이트 안내 > 공지 배너
      final shown = await _tryShowUpdate(context, theme, data);
      if (!context.mounted) return;
      if (!shown) {
        await _tryShowAnnouncement(context, theme, data);
      }
    } catch (e) {
      debugPrint('[StartupPopup] error: $e');
    }
  }

  static Future<bool> _tryShowUpdate(
      BuildContext context, TteolgaTheme theme, Map<String, dynamic> data) async {
    final update = data['updateNotice'];
    if (update is! Map<String, dynamic>) return false;
    if (update['active'] != true) return false;

    final latestVersion = update['latestVersion'] as String?;
    if (latestVersion == null || latestVersion.isEmpty) return false;

    final packageInfo = await PackageInfo.fromPlatform();
    if (!_isNewer(latestVersion, packageInfo.version)) return false;

    final forceUpdate = update['forceUpdate'] == true;

    // forceUpdate가 아니면 같은 버전 dismiss 여부 확인
    if (!forceUpdate) {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_keyUpdateDismissedVersion) == latestVersion) {
        return false;
      }
    }

    if (!context.mounted) return false;
    await showUpdateDialog(
      context,
      theme: theme,
      title: update['title'] as String? ?? '업데이트 안내',
      body: update['body'] as String? ?? '새로운 버전이 출시되었습니다.',
      updateUrl: update['updateUrl'] as String? ?? '',
      forceUpdate: forceUpdate,
    );

    // forceUpdate가 아닐 때만 dismiss 기록
    if (!forceUpdate) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyUpdateDismissedVersion, latestVersion);
    }
    return true;
  }

  static Future<bool> _tryShowAnnouncement(
      BuildContext context, TteolgaTheme theme, Map<String, dynamic> data) async {
    final announcement = data['announcement'];
    if (announcement is! Map<String, dynamic>) return false;
    if (announcement['active'] != true) return false;

    final id = announcement['id'] as String?;
    if (id == null || id.isEmpty) return false;

    // 같은 id + 같은 날짜면 표시하지 않음 (하루 1회)
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final shownDate = prefs.getString(_keyAnnouncementShownDate);
    if (shownDate == '${id}_$today') return false;

    if (!context.mounted) return false;
    AnalyticsService.logAnnouncementImpression(id);
    ClickTracker.track('announcement_impression');
    await showAnnouncementDialog(
      context,
      theme: theme,
      title: announcement['title'] as String? ?? '',
      body: announcement['body'] as String? ?? '',
      imageUrl: announcement['imageUrl'] as String?,
      ctaUrl: announcement['ctaUrl'] as String?,
      ctaLabel: announcement['ctaLabel'] as String?,
      announcementId: id,
    );

    await prefs.setString(_keyAnnouncementShownDate, '${id}_$today');
    return true;
  }

  /// 시맨틱 버전 비교: latest > current 이면 true
  static bool _isNewer(String latest, String current) {
    final latestParts = latest.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final currentParts = current.split('.').map((s) => int.tryParse(s) ?? 0).toList();

    for (int i = 0; i < 3; i++) {
      final l = i < latestParts.length ? latestParts[i] : 0;
      final c = i < currentParts.length ? currentParts[i] : 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    return false;
  }
}
