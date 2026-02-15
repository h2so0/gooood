import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// 네이티브 앱 우선 시도, 없으면 브라우저로 폴백
Future<void> launchProductUrl(String url) async {
  if (url.isEmpty) return;
  final uri = Uri.parse(url);
  try {
    // 네이티브 앱(네이버 등)으로 먼저 시도
    final opened = await launchUrl(uri, mode: LaunchMode.externalNonBrowserApplication);
    if (opened) return;
  } catch (_) {
    // 앱이 없으면 예외 발생 — 무시하고 브라우저로 폴백
  }
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('[UrlLauncher] launch failed: $e');
  }
}
