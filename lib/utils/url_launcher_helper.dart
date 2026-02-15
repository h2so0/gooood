import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// 네이티브 앱 우선 시도, 없으면 브라우저로 폴백
Future<void> launchProductUrl(String url) async {
  if (url.isEmpty) return;

  final uri = Uri.parse(url);
  final scheme = _appScheme(uri.host);

  if (scheme != null) {
    final appUri = Uri.parse(
      '$scheme://inappbrowser?url=${Uri.encodeComponent(url)}',
    );
    try {
      final opened = await launchUrl(appUri);
      if (opened) return;
    } catch (_) {}
  }

  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('[UrlLauncher] launch failed: $e');
  }
}

String? _appScheme(String host) {
  if (host.endsWith('naver.com') || host.endsWith('naver.net')) {
    return 'naversearchapp';
  }
  if (host.endsWith('11st.co.kr')) return 'elevenstapp';
  if (host.endsWith('gmarket.co.kr')) return 'gmarket';
  if (host.endsWith('auction.co.kr')) return 'auction';
  return null;
}
