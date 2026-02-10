import 'package:flutter/material.dart';
import '../../models/product.dart';
import '../../theme/app_theme.dart';
import '../../widgets/product_image.dart';

class HeroImageSection extends StatelessWidget {
  final Product product;
  final TteolgaTheme theme;
  final VoidCallback onBack;
  final VoidCallback onShare;

  const HeroImageSection({
    super.key,
    required this.product,
    required this.theme,
    required this.onBack,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: ProductImage(
            imageUrl: product.imageUrl,
            fit: BoxFit.cover,
            errorIcon: Icons.shopping_bag_outlined,
            errorIconSize: 48,
          ),
        ),
        // 상단 그라데이션
        Positioned(
          top: 0, left: 0, right: 0,
          height: MediaQuery.of(context).padding.top + 56,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.45),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        // 네비 버튼
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 12, right: 12,
          child: Row(
            children: [
              _overlayButton(
                icon: Icons.arrow_back_ios_new,
                onTap: onBack,
              ),
              const Spacer(),
              _overlayButton(
                icon: Icons.ios_share,
                onTap: onShare,
              ),
            ],
          ),
        ),
        // BEST 순위
        if (product.rank != null)
          Positioned(
            bottom: 12, right: 12,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'BEST #${product.rank}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _overlayButton(
      {required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 16, color: Colors.white),
      ),
    );
  }
}
