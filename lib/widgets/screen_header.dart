import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'app_icon_button.dart';

/// 뒤로가기 + 중앙 제목 헤더 (settings, wishlist 등)
class ScreenHeader extends StatelessWidget {
  final TteolgaTheme theme;
  final String title;

  const ScreenHeader({
    super.key,
    required this.theme,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return SizedBox(
      height: 38,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: AppIconButton(
              icon: Icons.arrow_back_ios_new,
              onTap: () => Navigator.of(context).pop(),
              backgroundColor: t.card,
              iconColor: t.textSecondary,
            ),
          ),
          Center(
            child: Text(title,
                style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
