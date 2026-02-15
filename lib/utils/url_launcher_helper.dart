import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// 외부 앱(네이버 등)으로 먼저 시도, 없으면 브라우저로 폴백
Future<void> launchProductUrl(String url) async {
  if (url.isEmpty) return;
  final uri = Uri.parse(url);
  try {
    await launchUrl(uri, mode: LaunchMode.externalNonBrowserApplication);
  } catch (_) {
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        debugPrint('[UrlLauncher] launchUrl returned false for: $url');
      }
    } catch (e) {
      debugPrint('[UrlLauncher] launch failed: $e');
    }
  }
}
