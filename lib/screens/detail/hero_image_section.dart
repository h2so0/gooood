import 'package:flutter/material.dart';
import '../../models/product.dart';
import '../../theme/app_theme.dart';
import '../../widgets/product_image.dart';

/// 고정 헤더 (뒤로가기 / 공유)
class DetailHeader extends StatelessWidget {
  final TteolgaTheme theme;
  final VoidCallback onBack;
  final VoidCallback onShare;

  const DetailHeader({
    super.key,
    required this.theme,
    required this.onBack,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final t = theme;

    return Container(
      color: t.surface,
      padding: EdgeInsets.only(
          top: topPadding + 8, bottom: 8, left: 12, right: 12),
      child: Row(
        children: [
          _headerButton(icon: Icons.arrow_back_ios_new, onTap: onBack),
          const Spacer(),
          _headerButton(icon: Icons.ios_share, onTap: onShare),
        ],
      ),
    );
  }

  Widget _headerButton(
      {required IconData icon, required VoidCallback onTap}) {
    final t = theme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: t.textPrimary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 16, color: t.textPrimary),
      ),
    );
  }
}

/// 스크롤 가능한 상품 이미지
class HeroImageSection extends StatelessWidget {
  final Product product;
  final TteolgaTheme theme;

  const HeroImageSection({
    super.key,
    required this.product,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final t = theme;

    return Container(
      color: t.surface,
      constraints: BoxConstraints(maxHeight: screenHeight * 0.48),
      width: double.infinity,
      child: ProductImage(
        imageUrl: product.imageUrl,
        fit: BoxFit.contain,
        errorIcon: Icons.shopping_bag_outlined,
        errorIconSize: 48,
      ),
    );
  }
}
