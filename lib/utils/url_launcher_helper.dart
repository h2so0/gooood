import 'package:url_launcher/url_launcher.dart';

/// 앱이 설치되어 있으면 앱으로, 없으면 브라우저로 열기
Future<void> launchProductUrl(String url) async {
  if (url.isEmpty) return;
  final uri = Uri.parse(url);
  try {
    await launchUrl(uri, mode: LaunchMode.externalNonBrowserApplication);
  } catch (_) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
