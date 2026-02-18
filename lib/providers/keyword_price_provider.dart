import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/keyword_price_data.dart';
import '../models/product.dart';
import '../services/keyword_price_analyzer.dart';
import '../services/keyword_price_tracker.dart';
import 'api_providers.dart';

/// 실시간 분석 엔진
final keywordPriceAnalyzerProvider = Provider<KeywordPriceAnalyzer>((ref) {
  final api = ref.watch(naverApiProvider);
  return KeywordPriceAnalyzer(api);
});

/// 일별 수집기 (Firestore 공유)
final keywordPriceTrackerProvider = Provider<KeywordPriceTracker>((ref) {
  final analyzer = ref.watch(keywordPriceAnalyzerProvider);
  return KeywordPriceTracker(analyzer);
});

/// 실시간 가격 분석 (히스토그램용) — 키워드만
final keywordPriceAnalysisProvider =
    FutureProvider.autoDispose.family<KeywordPriceSnapshot, String>(
        (ref, keyword) async {
  final analyzer = ref.watch(keywordPriceAnalyzerProvider);
  return analyzer.analyze(keyword);
});

/// 실시간 가격 분석 (히스토그램용) — 상품 컨텍스트 포함
final keywordPriceAnalysisWithProductProvider = FutureProvider.autoDispose
    .family<KeywordPriceSnapshot, ({String keyword, Product product})>(
        (ref, params) async {
  final analyzer = ref.watch(keywordPriceAnalyzerProvider);
  return analyzer.analyze(params.keyword, originalProduct: params.product);
});

/// Firestore 히스토리 (라인차트용)
final keywordPriceHistoryProvider =
    FutureProvider.autoDispose.family<List<KeywordPriceSummary>, String>(
        (ref, keyword) async {
  final tracker = ref.watch(keywordPriceTrackerProvider);
  return tracker.getHistory(keyword);
});
