import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/app_theme.dart';
import '../utils/image_helper.dart';

/// CachedNetworkImage + proxyImage + placeholder/error 패턴 통합
class ProductImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit fit;
  final IconData? errorIcon;
  final double? errorIconSize;

  const ProductImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.errorIcon,
    this.errorIconSize,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final t = isDark ? TteolgaTheme.dark : TteolgaTheme.light;

    if (imageUrl.isEmpty) {
      return Container(
        color: t.surface,
        child: errorIcon != null
            ? Center(
                child: Icon(errorIcon,
                    color: t.textTertiary, size: errorIconSize ?? 28))
            : null,
      );
    }

    return CachedNetworkImage(
      imageUrl: proxyImage(imageUrl),
      fit: fit,
      placeholder: (_, _) => Container(color: t.surface),
      errorWidget: (_, _, _) => Container(
        color: t.surface,
        child: errorIcon != null
            ? Center(
                child: Icon(errorIcon,
                    color: t.textTertiary, size: errorIconSize ?? 28))
            : null,
      ),
    );
  }
}
