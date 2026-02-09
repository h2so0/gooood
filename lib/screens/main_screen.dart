import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../widgets/product_card.dart';
import '../providers/product_provider.dart';
import '../models/product.dart';
import '../services/naver_shopping_api.dart';
import 'product_detail_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _tabIndex = 0;

  static const _tabs = [
    '홈',
    '디지털/가전',
    '패션/의류',
    '생활/건강',
    '식품',
    '뷰티',
    '스포츠/레저',
    '출산/육아',
    '반려동물',
  ];

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tteolgaThemeProvider);
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: t.bg,
      body: Column(
        children: [
          SizedBox(height: topPadding + 10),

          // Search bar + settings
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const SearchScreen()),
                    ),
                    child: Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: t.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: t.border, width: 0.5),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search,
                              color: t.textTertiary, size: 20),
                          const SizedBox(width: 10),
                          Text('상품명을 검색하세요',
                              style: TextStyle(
                                  color: t.textTertiary, fontSize: 14)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const SettingsScreen()),
                  ),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: t.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: t.border, width: 0.5),
                    ),
                    child: Icon(Icons.settings_outlined,
                        color: t.textTertiary, size: 20),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Category tabs
          SizedBox(
            height: 36,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _tabs.length,
              itemBuilder: (context, i) {
                final selected = i == _tabIndex;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _tabIndex = i),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: selected
                            ? t.textPrimary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(18),
                        border: selected
                            ? null
                            : Border.all(color: t.border, width: 0.5),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _tabs[i],
                        style: TextStyle(
                          color:
                              selected ? t.bg : t.textSecondary,
                          fontSize: 13,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          // Content
          Expanded(
            child: _tabIndex == 0
                ? _HomeFeed(onTap: _openDetail)
                : _CategoryFeed(
                    category: _tabs[_tabIndex],
                    onTap: _openDetail,
                  ),
          ),
        ],
      ),
    );
  }

  void _openDetail(Product p) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(product: p),
      ),
    );
  }
}

/// 홈 피드: 롤링 인기 검색어 + 핫딜 그리드
class _HomeFeed extends ConsumerStatefulWidget {
  final void Function(Product) onTap;
  const _HomeFeed({required this.onTap});

  @override
  ConsumerState<_HomeFeed> createState() => _HomeFeedState();
}

class _HomeFeedState extends ConsumerState<_HomeFeed> {
  bool _trendExpanded = false;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tteolgaThemeProvider);
    final hotProducts = ref.watch(hotProductsProvider);
    final trendKeywords = ref.watch(trendKeywordsProvider);

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(top: 8),
      children: [
        // ── 인기 검색어 (롤링 바 + 펼치기) ──
        trendKeywords.when(
          data: (keywords) {
            if (keywords.isEmpty) return const SizedBox();
            return _buildTrendBar(t, keywords);
          },
          loading: () => const SizedBox(height: 44),
          error: (_, __) => const SizedBox(),
        ),

        const SizedBox(height: 16),

        // ── 오늘의 핫딜 (그리드) ──
        _sectionTitle(t, '오늘의 핫딜'),
        const SizedBox(height: 10),
        hotProducts.when(
          data: (products) {
            if (products.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text('핫딜 상품을 불러오는 중...',
                    style:
                        TextStyle(color: t.textTertiary, fontSize: 13)),
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.62,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: products.length,
                itemBuilder: (context, i) => ProductGridCard(
                  product: products[i],
                  onTap: () => widget.onTap(products[i]),
                ),
              ),
            );
          },
          loading: () => SizedBox(
            height: 200,
            child: Center(
                child:
                    CircularProgressIndicator(color: t.textTertiary)),
          ),
          error: (_, __) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('불러오기 실패',
                style: TextStyle(color: t.textSecondary)),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildTrendBar(TteolgaTheme t, List<TrendKeyword> keywords) {
    if (_trendExpanded) {
      // 펼쳐진 상태: 전체 키워드 리스트
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: t.border, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('인기 검색어',
                      style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => _trendExpanded = false),
                    child: Icon(Icons.keyboard_arrow_up,
                        color: t.textTertiary, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: keywords.take(20).toList().asMap().entries.map((e) {
                  return GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const SearchScreen()),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: t.border, width: 0.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${e.key + 1}',
                              style: TextStyle(
                                  color: t.textTertiary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(width: 4),
                          Text(e.value.keyword,
                              style: TextStyle(
                                  color: t.textSecondary, fontSize: 13)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      );
    }

    // 접힌 상태: 한줄 롤링
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.border, width: 0.5),
        ),
        child: Row(
          children: [
            Text('인기',
                style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
            const SizedBox(width: 10),
            Expanded(
              child: _RollingKeywords(keywords: keywords),
            ),
            GestureDetector(
              onTap: () => setState(() => _trendExpanded = true),
              child: Icon(Icons.keyboard_arrow_down,
                  color: t.textTertiary, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(TteolgaTheme t, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Text(
        title,
        style: TextStyle(
          color: t.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 한줄 롤링 인기 검색어
class _RollingKeywords extends StatefulWidget {
  final List<TrendKeyword> keywords;
  const _RollingKeywords({required this.keywords});

  @override
  State<_RollingKeywords> createState() => _RollingKeywordsState();
}

class _RollingKeywordsState extends State<_RollingKeywords> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _startRolling();
  }

  void _startRolling() {
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _currentIndex =
            (_currentIndex + 1) % widget.keywords.length;
      });
      _startRolling();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.keywords.isEmpty) return const SizedBox();
    final kw = widget.keywords[_currentIndex];
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.5),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: Row(
        key: ValueKey(_currentIndex),
        children: [
          Text(
            '${_currentIndex + 1}',
            style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white54
                  : Colors.black38,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              kw.keyword,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white70
                    : Colors.black87,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 카테고리 피드 (pull-to-refresh)
class _CategoryFeed extends ConsumerWidget {
  final String category;
  final void Function(Product) onTap;
  const _CategoryFeed({required this.category, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tteolgaThemeProvider);
    final products = ref.watch(categoryDealsProvider(category));

    return products.when(
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Text('상품이 없습니다',
                style: TextStyle(color: t.textTertiary)),
          );
        }
        return RefreshIndicator(
          color: t.textPrimary,
          backgroundColor: t.card,
          onRefresh: () async {
            ref.invalidate(categoryDealsProvider(category));
          },
          child: GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.62,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) => ProductGridCard(
              product: items[i],
              onTap: () => onTap(items[i]),
            ),
          ),
        );
      },
      loading: () => Center(
        child: CircularProgressIndicator(color: t.textTertiary),
      ),
      error: (_, __) => Center(
        child: Text('불러오기 실패',
            style: TextStyle(color: t.textTertiary)),
      ),
    );
  }
}
