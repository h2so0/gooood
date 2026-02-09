import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../widgets/product_card.dart';
import '../providers/product_provider.dart';
import 'product_detail_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';

  static const _fallbackPopular = [
    '냉장고', '노트북', '가습기', '에어프라이어',
    '블루투스스피커', '무선청소기', '원피스', '트위드자켓',
  ];

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      setState(() => _query = value.trim());
    });
  }

  void _search(String keyword) {
    _controller.text = keyword;
    setState(() => _query = keyword);
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
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Icon(Icons.arrow_back_ios_new,
                      size: 18, color: t.textSecondary),
                ),
                const SizedBox(width: 12),
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
                      autofocus: true,
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
    final keywords = trends.when(
      data: (list) =>
          list.map((tk) => tk.keyword).toList(),
      loading: () => _fallbackPopular,
      error: (_, __) => _fallbackPopular,
    );

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        const SizedBox(height: 16),
        Text('인기 검색어',
            style: TextStyle(
                color: t.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: keywords.map((k) {
            return GestureDetector(
              onTap: () => _search(k),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: t.border, width: 0.5),
                ),
                child: Text(k,
                    style:
                        TextStyle(color: t.textSecondary, fontSize: 13)),
              ),
            );
          }).toList(),
        ),
      ],
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
          },
          child: GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.62,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: products.length,
            itemBuilder: (context, i) => ProductGridCard(
              product: products[i],
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProductDetailScreen(product: products[i]),
                ),
              ),
            ),
          ),
        );
      },
      loading: () =>
          Center(child: CircularProgressIndicator(color: t.textTertiary)),
      error: (e, _) => Center(
          child: Text('검색 실패',
              style: TextStyle(color: t.textSecondary))),
    );
  }
}
