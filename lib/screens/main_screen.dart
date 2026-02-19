import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../models/product.dart';
import '../providers/keyword_wishlist_provider.dart';
import 'detail/product_detail_screen.dart';
import 'search_screen.dart';
import 'settings/settings_screen.dart';
import 'wishlist/keyword_wishlist_screen.dart';
import 'home/home_feed.dart';
import 'category_feed.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _tabIndex = 0;
  final Set<int> _visitedTabs = {0}; // 홈만 먼저 빌드

  static const _tabs = [
    '홈',
    '디지털/가전',
    '패션/의류',
    '생활/건강',
    '식품',
    '뷰티',
    '스포츠/레저',
    '출산/육아',
  ];

  @override
  void initState() {
    super.initState();
    // 홈 렌더링 후 1초 뒤 나머지 카테고리 프리페치
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() {
        for (int i = 1; i < _tabs.length; i++) {
          _visitedTabs.add(i);
        }
      });
    });
  }

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
                // 찜 버튼
                GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const KeywordWishlistScreen()),
                  ),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: t.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: t.border, width: 0.5),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(Icons.bookmark_outline,
                            color: t.textTertiary, size: 20),
                        // 뱃지
                        Consumer(builder: (context, ref, _) {
                          final count =
                              ref.watch(keywordWishlistProvider).length;
                          if (count == 0) return const SizedBox.shrink();
                          final label = count > 9 ? '9+' : '$count';
                          return Positioned(
                            top: 4,
                            right: 4,
                            child: Container(
                              constraints: const BoxConstraints(
                                minWidth: 16,
                                minHeight: 16,
                              ),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: t.drop,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                label,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    height: 1.1),
                              ),
                            ),
                          );
                        }),
                      ],
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
                    onTap: () => setState(() {
                      _tabIndex = i;
                      _visitedTabs.add(i);
                    }),
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

          // Content — 방문한 탭은 IndexedStack으로 유지 (재로딩 방지)
          Expanded(
            child: IndexedStack(
              index: _tabIndex,
              children: List.generate(_tabs.length, (i) {
                if (!_visitedTabs.contains(i)) {
                  return const SizedBox.shrink();
                }
                return i == 0
                    ? HomeFeed(onTap: _openDetail)
                    : CategoryFeed(
                        category: _tabs[i],
                        onTap: _openDetail,
                      );
              }),
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
