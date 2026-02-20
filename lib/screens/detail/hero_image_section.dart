import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../models/product.dart';
import '../../theme/app_theme.dart';
import '../../utils/image_helper.dart';
import '../../widgets/app_icon_button.dart';
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
    return AppIconButton(
      icon: icon,
      onTap: onTap,
      backgroundColor: t.textPrimary.withValues(alpha: 0.06),
      iconColor: t.textPrimary,
    );
  }
}

/// 스크롤 가능한 상품 이미지
class HeroImageSection extends StatefulWidget {
  final Product product;
  final TteolgaTheme theme;

  const HeroImageSection({
    super.key,
    required this.product,
    required this.theme,
  });

  @override
  State<HeroImageSection> createState() => _HeroImageSectionState();
}

class _HeroImageSectionState extends State<HeroImageSection> {
  double? _imageAspectRatio;

  @override
  void initState() {
    super.initState();
    // 그리드 카드에서 이미 로드한 이미지의 aspect ratio 캐시 확인
    _imageAspectRatio = getCachedAspectRatio(widget.product.imageUrl);
    if (_imageAspectRatio == null) {
      _resolveImageSize();
    }
  }

  void _resolveImageSize() {
    final url = proxyImage(widget.product.imageUrl);
    if (url.isEmpty) return;
    final provider = CachedNetworkImageProvider(url);
    final stream = provider.resolve(ImageConfiguration.empty);
    stream.addListener(ImageStreamListener((info, _) {
      final ratio = info.image.width / info.image.height;
      cacheAspectRatio(widget.product.imageUrl, ratio);
      if (mounted && _imageAspectRatio == null) {
        setState(() => _imageAspectRatio = ratio);
      }
    }));
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.48;
    final t = widget.theme;

    final double height;
    if (_imageAspectRatio != null) {
      height = (screenWidth / _imageAspectRatio!).clamp(0.0, maxHeight);
    } else {
      height = maxHeight;
    }

    return Container(
      color: t.surface,
      height: height,
      width: double.infinity,
      child: ProductImage(
        imageUrl: widget.product.imageUrl,
        fit: BoxFit.contain,
        errorIcon: Icons.shopping_bag_outlined,
        errorIconSize: 48,
        memCacheWidth: (screenWidth *
                MediaQuery.devicePixelRatioOf(context))
            .toInt(),
      ),
    );
  }
}
