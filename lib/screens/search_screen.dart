import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../services/analytics_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/product_card.dart';
import '../widgets/keyword_price_section.dart';
import '../providers/providers.dart';
import 'detail/product_detail_screen.dart';
import 'home/trend_section.dart';

class SearchScreen extends ConsumerStatefulWidget {
  final String? initialQuery;
  final bool autofocus;
  const SearchScreen({super.key, this.initialQuery, this.autofocus = true});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _controller.text = widget.initialQuery!;
      _query = widget.initialQuery!;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      final trimmed = value.trim();
      setState(() => _query = trimmed);
      if (trimmed.isNotEmpty) AnalyticsService.logSearch(trimmed);
    });
  }

  void _search(String keyword) {
    FocusScope.of(context).unfocus();
    _controller.text = keyword;
    setState(() => _query = keyword);
    AnalyticsService.logSearch(keyword);
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

          // Search bar with back button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                AppIconButton(
                  icon: Icons.arrow_back_ios_new,
                  onTap: () => Navigator.of(context).pop(),
                  backgroundColor: t.card,
                  iconColor: t.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: t.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: t.border, width: 0.5),
                    ),
                    child: TextField(
                      controller: _controller,
                      onChanged: _onChanged,
                      autofocus: widget.autofocus,
                      style:
                          TextStyle(color: t.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: '상품명을 검색하세요',
                        hintStyle: TextStyle(
                            color: t.textTertiary, fontSize: 14),
                        prefixIcon: Icon(Icons.search,
                            color: t.textTertiary, size: 20),
                        suffixIcon: _controller.text.isNotEmpty
                            ? GestureDetector(
                                onTap: () {
                                  _controller.clear();
                                  setState(() => _query = '');
                                },
                                child: Icon(Icons.close,
                                    color: t.textTertiary, size: 18),
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 0, vertical: 11),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          Expanded(
            child: _query.isEmpty ? _buildIdle(t) : _buildResults(t),
          ),
        ],
      ),
    );
  }

  Widget _buildIdle(TteolgaTheme t) {
    final trends = ref.watch(trendKeywordsProvider);

    return trends.when(
      data: (keywords) {
        if (keywords.isEmpty) {
          return Center(
            child: Text('인기 검색어가 없습니다',
                style: TextStyle(color: t.textTertiary, fontSize: 13)),
          );
        }
        return ListView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            const SizedBox(height: 4),
            TrendSection(
              keywords: keywords,
              theme: t,
              onKeywordTap: _search,
            ),
          ],
        );
      },
      loading: () =>
          Center(child: CircularProgressIndicator(color: t.textTertiary)),
      error: (_, _) => Center(
        child: Text('인기 검색어를 불러올 수 없습니다',
            style: TextStyle(color: t.textTertiary, fontSize: 13)),
      ),
    );
  }

  Widget _buildResults(TteolgaTheme t) {
    final results = ref.watch(searchResultsProvider(_query));

    return results.when(
      data: (products) {
        if (products.isEmpty) {
          return Center(
            child: Text('"$_query" 검색 결과가 없습니다',
                style: TextStyle(color: t.textSecondary)),
          );
        }
        return RefreshIndicator(
          color: t.textPrimary,
          backgroundColor: t.card,
          onRefresh: () async {
            ref.invalidate(searchResultsProvider(_query));
            ref.invalidate(keywordPriceAnalysisProvider(_query));
            ref.invalidate(keywordPriceHistoryProvider(_query));
          },
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            slivers: [
              // 가격 분석 섹션
              SliverToBoxAdapter(
                child: KeywordPriceSection(keyword: _query),
              ),

              // 기존 상품 그리드
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                sliver: SliverMasonryGrid.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childCount: products.length,
                  itemBuilder: (context, i) => ProductGridCard(
                    product: products[i],
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            ProductDetailScreen(product: products[i]),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () =>
          Center(child: CircularProgressIndicator(color: t.textTertiary)),
      error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off, color: t.textTertiary, size: 40),
              const SizedBox(height: 12),
              Text('검색에 실패했어요',
                  style: TextStyle(color: t.textSecondary, fontSize: 14)),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => ref.invalidate(searchResultsProvider(_query)),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: t.border),
                  ),
                  child: Text('다시 시도',
                      style: TextStyle(
                          color: t.textPrimary, fontSize: 13)),
                ),
              ),
            ],
          )),
    );
  }
}
