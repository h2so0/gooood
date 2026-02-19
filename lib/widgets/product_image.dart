import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../utils/image_helper.dart';

/// CachedNetworkImage + proxyImage + placeholder/error 패턴 통합
class ProductImage extends ConsumerWidget {
  final String imageUrl;
  final BoxFit fit;
  final IconData? errorIcon;
  final double? errorIconSize;
  final int? memCacheWidth;

  const ProductImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.errorIcon,
    this.errorIconSize,
    this.memCacheWidth,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tteolgaThemeProvider);

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

    // 디바이스 픽셀 비율 반영하여 메모리 캐시 해상도 제한
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = memCacheWidth ?? (200 * dpr).toInt();

    return CachedNetworkImage(
      imageUrl: proxyImage(imageUrl),
      fit: fit,
      memCacheWidth: cacheWidth,
      fadeInDuration: const Duration(milliseconds: 150),
      placeholderFadeInDuration: Duration.zero,
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
