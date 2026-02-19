import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 앱 공용 SnackBar 표시 헬퍼
void showAppSnackBar(BuildContext context, TteolgaTheme t, String message) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(fontSize: 13)),
      backgroundColor: t.card,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
}
