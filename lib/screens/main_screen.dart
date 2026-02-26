import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/analytics_service.dart';
import '../theme/app_theme.dart';
import '../models/product.dart';
import '../providers/trend_provider.dart';
import 'detail/product_detail_screen.dart';
import 'daily_best_screen.dart';
import 'search_screen.dart';
import 'settings/settings_screen.dart';
import 'home/home_feed.dart';
import 'home/rolling_keywords.dart';
import 'home/time_deal_feed.dart';
import 'category_feed.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _tabIndex = 0;
  final Set<int> _visitedTabs = {0}; // 홈만 먼저 빌드
  bool _isOffline = false;
  bool _showSearchBar = true;
  double _lastScrollOffset = 0;
  late final StreamSubscription<List<ConnectivityResult>> _connectivitySub;
  late final List<ScrollController> _scrollControllers;

  static const _tabs = [
    '홈',
    '타임딜',
    '디지털/가전',
    '패션/의류',
    '생활/건강',
    '식품',
    '뷰티',
    '스포츠/레저',
    '출산/육아',
  ];

  late final List<void Function()> _scrollListeners;

  void _onFeedScroll(int scrollIndex) {
    // Ignore scroll events from non-active tabs
    if (scrollIndex != _tabIndex) return;
    final sc = _scrollControllers[scrollIndex];
    if (!sc.hasClients) return;
    final offset = sc.offset;
    final delta = offset - _lastScrollOffset;
    _lastScrollOffset = offset;

    if (offset <= 0) {
      if (!_showSearchBar) setState(() => _showSearchBar = true);
    } else if (delta > 4 && _showSearchBar) {
      setState(() => _showSearchBar = false);
    } else if (delta < -4 && !_showSearchBar) {
      setState(() => _showSearchBar = true);
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollControllers = List.generate(_tabs.length, (_) => ScrollController());
    _scrollListeners = List.generate(
      _tabs.length,
      (i) => () => _onFeedScroll(i),
    );
    for (int i = 0; i < _tabs.length; i++) {
      _scrollControllers[i].addListener(_scrollListeners[i]);
    }
    // 홈 렌더링 후 점진적 탭 프리페치 (2개씩 500ms 간격)
    _prefetchTabs();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final offline = results.every((r) => r == ConnectivityResult.none);
      if (offline != _isOffline) setState(() => _isOffline = offline);
    });
  }

  Future<void> _prefetchTabs() async {
    await Future.delayed(const Duration(seconds: 1));
    for (int i = 1; i < _tabs.length; i += 2) {
      if (!mounted) return;
      setState(() {
        _visitedTabs.add(i);
        if (i + 1 < _tabs.length) _visitedTabs.add(i + 1);
      });
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  @override
  void dispose() {
    _connectivitySub.cancel();
    for (int i = 0; i < _scrollControllers.length; i++) {
      _scrollControllers[i].removeListener(_scrollListeners[i]);
      _scrollControllers[i].dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tteolgaThemeProvider);
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: t.bg,
      body: Column(
        children: [
          SizedBox(height: topPadding + 6),

          // Search bar + 인기 키워드 통합 (스크롤 시 숨김)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            height: _showSearchBar ? 52 : 0,
            clipBehavior: Clip.hardEdge,
            decoration: const BoxDecoration(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
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
                            // 인기 키워드 롤링 (모든 탭 공통)
                            Expanded(
                              child: Consumer(builder: (context, ref, _) {
                                final trendAsync =
                                    ref.watch(trendKeywordsProvider);
                                return trendAsync.when(
                                  data: (keywords) {
                                    if (keywords.isEmpty) {
                                      return Text('상품명을 검색하세요',
                                          style: TextStyle(
                                              color: t.textTertiary,
                                              fontSize: 14));
                                    }
                                    return RollingKeywords(
                                      keywords: keywords,
                                      onTap: (keyword) {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                SearchScreen(initialQuery: keyword, autofocus: false),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                  loading: () => Text('상품명을 검색하세요',
                                      style: TextStyle(
                                          color: t.textTertiary,
                                          fontSize: 14)),
                                  error: (_, _) => Text('상품명을 검색하세요',
                                      style: TextStyle(
                                          color: t.textTertiary,
                                          fontSize: 14)),
                                );
                              }),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 오늘의 BEST 버튼
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const DailyBestScreen()),
                    ),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: t.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: t.border, width: 0.5),
                      ),
                      child: Icon(Icons.emoji_events_outlined,
                          color: t.textTertiary, size: 20),
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
          ),

          // Category tabs — underline style
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _tabs.length,
              itemBuilder: (context, i) {
                final selected = i == _tabIndex;
                return GestureDetector(
                  onTap: () {
                    if (i == _tabIndex) return;
                    final sc = _scrollControllers[i];
                    _lastScrollOffset = sc.hasClients ? sc.offset : 0;
                    setState(() {
                      _tabIndex = i;
                      _visitedTabs.add(i);
                      _showSearchBar = true;
                    });
                    AnalyticsService.logCategoryChanged(_tabs[i]);
                  },
                  child: Container(
                    color: Colors.transparent,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: IntrinsicWidth(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_tabs[i] == '타임딜') ...[
                                Icon(Icons.timer,
                                    size: 12,
                                    color: selected
                                        ? t.textPrimary
                                        : t.textTertiary),
                                const SizedBox(width: 3),
                              ],
                              Text(
                                _tabs[i],
                                style: TextStyle(
                                  color: selected
                                      ? t.textPrimary
                                      : t.textTertiary,
                                  fontSize: 14,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: selected ? 2 : 0,
                            decoration: BoxDecoration(
                              color: t.textPrimary,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // 오프라인 배너
          if (_isOffline)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6),
              color: t.drop.withValues(alpha: 0.15),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.wifi_off, size: 14, color: t.drop),
                  const SizedBox(width: 6),
                  Text('오프라인 상태입니다',
                      style: TextStyle(color: t.drop, fontSize: 12)),
                ],
              ),
            ),

          // Content — 방문한 탭은 IndexedStack으로 유지 (재로딩 방지)
          Expanded(
            child: IndexedStack(
              index: _tabIndex,
              children: List.generate(_tabs.length, (i) {
                if (!_visitedTabs.contains(i)) {
                  return const SizedBox.shrink();
                }
                if (i == 0) {
                  return HomeFeed(
                    onTap: _openDetail,
                    scrollController: _scrollControllers[i],
                  );
                }
                if (i == 1) {
                  return TimeDealFeed(
                    onTap: _openDetail,
                    scrollController: _scrollControllers[i],
                  );
                }
                return CategoryFeed(
                  category: _tabs[i],
                  onTap: _openDetail,
                  scrollController: _scrollControllers[i],
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
