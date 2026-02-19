import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';

/// 시머 애니메이션이 적용된 기본 박스
class ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// 시머 애니메이션 래퍼
class Shimmer extends StatefulWidget {
  final Widget child;
  final Color baseColor;
  final Color highlightColor;

  const Shimmer({
    super.key,
    required this.child,
    required this.baseColor,
    required this.highlightColor,
  });

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            final dx = _controller.value * 2 - 0.5;
            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                widget.baseColor,
                widget.highlightColor,
                widget.baseColor,
              ],
              stops: [
                (dx - 0.3).clamp(0.0, 1.0),
                dx.clamp(0.0, 1.0),
                (dx + 0.3).clamp(0.0, 1.0),
              ],
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcIn,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// 스켈레톤 상품 카드 (ProductGridCard와 동일한 레이아웃)
class SkeletonProductCard extends StatelessWidget {
  final double imageAspect;
  const SkeletonProductCard({super.key, this.imageAspect = 1.0});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 이미지 영역
          AspectRatio(
            aspectRatio: imageAspect,
            child: Container(
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
            ),
          ),
          // 텍스트 영역
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 상점명
                Container(
                  width: 50,
                  height: 10,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                // 상품명 1줄
                Container(
                  width: double.infinity,
                  height: 12,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 4),
                // 상품명 2줄
                Container(
                  width: 80,
                  height: 12,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                // 가격
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 18,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 70,
                      height: 18,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 홈피드 전체 스켈레톤 (트렌드바 + 배너 + 상품그리드)
class SkeletonHomeFeed extends ConsumerWidget {
  const SkeletonHomeFeed({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tteolgaThemeProvider);
    final isDark = t.brightness == Brightness.dark;
    final baseColor = isDark ? const Color(0xFF1A1A1A) : const Color(0xFFE0E0E0);
    final highlightColor =
        isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF0F0F0);

    return Shimmer(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          const SizedBox(height: 6),
          // 트렌드 바 스켈레톤
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 배너 스켈레톤
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // 섹션 타이틀 스켈레톤
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              width: 120,
              height: 22,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 상품 그리드 스켈레톤 (메이슨리 2열)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _SkeletonMasonryGrid(),
          ),
        ],
      ),
    );
  }
}

/// 공통 스켈레톤 상품 카드 (메이슨리 + 그리드 공용)
class _SkeletonCard extends StatelessWidget {
  final double imageAspect;
  const _SkeletonCard({this.imageAspect = 1.0});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: imageAspect,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(16)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                    width: 50,
                    height: 10,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4))),
                const SizedBox(height: 6),
                Container(
                    width: double.infinity,
                    height: 12,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4))),
                const SizedBox(height: 4),
                Container(
                    width: 80,
                    height: 12,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4))),
                const SizedBox(height: 8),
                Row(children: [
                  Container(
                      width: 40,
                      height: 18,
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4))),
                  const SizedBox(width: 6),
                  Container(
                      width: 70,
                      height: 18,
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4))),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 메이슨리 스타일 스켈레톤 그리드 (왼/오른 컬럼 높이가 다름)
class _SkeletonMasonryGrid extends StatelessWidget {
  static const _leftAspects = [1.0, 0.8, 1.1, 0.9];
  static const _rightAspects = [0.85, 1.05, 0.75, 1.0];

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            children: _leftAspects
                .map((a) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _SkeletonCard(imageAspect: a),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            children: _rightAspects
                .map((a) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _SkeletonCard(imageAspect: a),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }
}

/// 상품 그리드만 스켈레톤 (카테고리 피드용 - 칩은 이미 실제 위젯으로 표시됨)
class SkeletonProductGrid extends StatelessWidget {
  final TteolgaTheme theme;
  const SkeletonProductGrid({super.key, required this.theme});

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    final baseColor =
        isDark ? const Color(0xFF1A1A1A) : const Color(0xFFE0E0E0);
    final highlightColor =
        isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF0F0F0);

    return Shimmer(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: List.generate(4, (row) {
            return Padding(
              padding: EdgeInsets.only(bottom: row < 3 ? 10 : 0),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                        child: _SkeletonCard(
                            imageAspect: row.isEven ? 1.0 : 0.85)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _SkeletonCard(
                            imageAspect: row.isEven ? 0.9 : 1.0)),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
