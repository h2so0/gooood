import 'package:flutter/material.dart';
import '../../models/trend_data.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_theme.dart';
import '../search_screen.dart';
import 'rolling_keywords.dart';

/// 인기 검색어 바 (접힘/펼침)
class TrendSection extends StatefulWidget {
  final List<TrendKeyword> keywords;
  final TteolgaTheme theme;
  const TrendSection({super.key, required this.keywords, required this.theme});

  @override
  State<TrendSection> createState() => _TrendSectionState();
}

class _TrendSectionState extends State<TrendSection> {
  bool _expanded = false;
  int _page = 0;
  final PageController _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _navigateToSearch(String keyword) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchScreen(initialQuery: keyword),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final keywords = widget.keywords;

    if (_expanded) {
      final pageCount = keywords.length > 10 ? 2 : 1;
      const pageHeight = 368.0;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: t.border, width: 0.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('인기 차트',
                      style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() {
                      _expanded = false;
                      _page = 0;
                    }),
                    child: Icon(Icons.keyboard_arrow_up,
                        color: t.textTertiary, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: pageHeight,
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: pageCount,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (_, i) =>
                      _buildTrendPage(t, keywords, i * 10),
                ),
              ),
              if (pageCount > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(pageCount, (i) {
                      return Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == _page
                              ? t.textPrimary
                              : t.textTertiary.withValues(alpha: 0.3),
                        ),
                      );
                    }),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: () {
          if (keywords.isNotEmpty) {
            AnalyticsService.logTrendingKeywordTap(
                keywords.first.keyword, rank: 1);
            _navigateToSearch(keywords.first.keyword);
          }
        },
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
                child: RollingKeywords(
                  keywords: keywords,
                  onTap: (keyword) {
                    final idx = keywords.indexWhere((k) => k.keyword == keyword);
                    AnalyticsService.logTrendingKeywordTap(
                        keyword, rank: idx + 1);
                    _navigateToSearch(keyword);
                  },
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _expanded = true),
                child: Icon(Icons.keyboard_arrow_down,
                    color: t.textTertiary, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrendPage(TteolgaTheme t, List<TrendKeyword> keywords, int offset) {
    final items = keywords.skip(offset).take(10).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: items.asMap().entries.map((e) {
        final rank = offset + e.key + 1;
        final kw = e.value;
        return GestureDetector(
          onTap: () {
            AnalyticsService.logTrendingKeywordTap(kw.keyword, rank: rank);
            _navigateToSearch(kw.keyword);
          },
          child: Container(
            color: Colors.transparent,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    '$rank',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: rank <= 3 ? t.textPrimary : t.textTertiary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    kw.keyword,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.textPrimary, fontSize: 14),
                  ),
                ),
                const SizedBox(width: 8),
                _buildRankChange(t, kw.rankChange),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRankChange(TteolgaTheme t, int? rankChange) {
    if (rankChange == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: t.rankUp.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'NEW',
          style: TextStyle(
            color: t.rankUp,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    if (rankChange == 0) {
      return Text('—',
          style: TextStyle(color: t.textTertiary, fontSize: 12));
    }
    final isUp = rankChange > 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isUp ? Icons.arrow_drop_up : Icons.arrow_drop_down,
          color: isUp ? t.rankUp : t.rankDown,
          size: 20,
        ),
        Text(
          '${rankChange.abs()}',
          style: TextStyle(
            color: isUp ? t.rankUp : t.rankDown,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
