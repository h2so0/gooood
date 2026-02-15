import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// 외부 브라우저(또는 인앱 브라우저)로 상품 URL 열기
Future<void> launchProductUrl(String url) async {
  if (url.isEmpty) return;
  final uri = Uri.parse(url);
  try {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      debugPrint('[UrlLauncher] launchUrl returned false for: $url');
    }
  } catch (e) {
    debugPrint('[UrlLauncher] launch failed: $e');
  }
}
