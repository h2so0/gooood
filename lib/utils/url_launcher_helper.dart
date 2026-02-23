import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// 네이티브 앱 우선 시도, 없으면 브라우저로 폴백
Future<void> launchProductUrl(String url) async {
  if (url.isEmpty) return;

  final uri = Uri.parse(url);
  final appUri = _buildAppUri(uri, url);

  if (appUri != null) {
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

Uri? _buildAppUri(Uri uri, String url) {
  final host = uri.host;

  // 네이버
  if (host.endsWith('naver.com') || host.endsWith('naver.net')) {
    return Uri.parse(
      'naversearchapp://inappbrowser?url=${Uri.encodeComponent(url)}',
    );
  }
  // 11번가
  if (host.endsWith('11st.co.kr')) {
    return Uri.parse(
      'elevenstapp://inappbrowser?url=${Uri.encodeComponent(url)}',
    );
  }
  // G마켓
  if (host.endsWith('gmarket.co.kr')) {
    return Uri.parse(
      'gmarket://inappbrowser?url=${Uri.encodeComponent(url)}',
    );
  }
  // 옥션
  if (host.endsWith('auction.co.kr')) {
    return Uri.parse(
      'auction://inappbrowser?url=${Uri.encodeComponent(url)}',
    );
  }
  // 롯데ON
  if (host.endsWith('lotteon.com')) {
    return Uri.parse(
      'lotteon://product?url=${Uri.encodeComponent(url)}',
    );
  }
  // SSG
  if (host.endsWith('ssg.com')) {
    return Uri.parse(
      'ssg://product?url=${Uri.encodeComponent(url)}',
    );
  }

  return null;
}
