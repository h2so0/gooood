import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../models/product.dart';
import 'product_detail_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'home/home_feed.dart';
import 'category_feed.dart';

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
                ? HomeFeed(onTap: _openDetail)
                : CategoryFeed(
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
