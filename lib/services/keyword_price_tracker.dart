import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/keyword_price_data.dart';
import '../models/keyword_wishlist.dart';
import '../utils/hive_helper.dart';
import 'cache/memory_cache.dart';
import 'keyword_price_analyzer.dart';
import 'notification_service.dart';

class KeywordPriceTracker {
  final KeywordPriceAnalyzer _analyzer;
  final MemoryCache _cache = MemoryCache();

  static const _metaBoxName = 'keyword_tracker_meta';
  static const _maxSnapshots = 90;

  KeywordPriceTracker(this._analyzer);

  /// 일별 스냅샷 수집 (하루 1회)
  Future<void> collectSnapshots(List<KeywordWishItem> wishItems) async {
    if (wishItems.isEmpty) return;

    final box = await _openMetaBox();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final lastDate = box.get('lastCollectDate') as String?;
    if (lastDate == today) return;

    for (final item in wishItems) {
      try {
        final snapshot = await _analyzer.analyze(item.keyword);
        if (snapshot.resultCount == 0) continue;

        final summary = snapshot.toSummary();
        await _saveToFirestore(item.keyword, summary);

        // 목표가 체크 → 알림
        if (item.targetPrice != null &&
            snapshot.minPrice > 0 &&
            snapshot.minPrice <= item.targetPrice!) {
          NotificationService().showKeywordPriceAlert(
            keyword: item.keyword,
            currentMin: snapshot.minPrice,
            targetPrice: item.targetPrice!,
          );
        }

        // rate limit
        await Future.delayed(const Duration(milliseconds: 300));
      } catch (e) {
        debugPrint('[KeywordTracker] collect error for ${item.keyword}: $e');
      }
    }

    await box.put('lastCollectDate', today);
  }

  /// Firestore에 요약 스냅샷 저장 (공유)
  Future<void> _saveToFirestore(
      String keyword, KeywordPriceSummary summary) async {
    final normalized = _normalizeKeyword(keyword);
    final docRef = FirebaseFirestore.instance
        .collection('keyword_snapshots')
        .doc(normalized);

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final doc = await tx.get(docRef);
      List<dynamic> snapshots = [];

      if (doc.exists) {
        snapshots =
            List<dynamic>.from(doc.data()?['snapshots'] as List? ?? []);
        // 같은 날짜 중복 방지
        snapshots.removeWhere((s) => s['date'] == summary.date);
      }

      snapshots.add(summary.toJson());

      // 날짜순 정렬 보장 후 90일 초과 제거
      snapshots.sort((a, b) =>
          (a['date'] as String? ?? '').compareTo(b['date'] as String? ?? ''));
      if (snapshots.length > _maxSnapshots) {
        snapshots = snapshots.sublist(snapshots.length - _maxSnapshots);
      }

      final data = {
        'lastCollectedAt': FieldValue.serverTimestamp(),
        'snapshots': snapshots,
      };

      if (doc.exists) {
        tx.update(docRef, data);
      } else {
        tx.set(docRef, {...data, 'trackerCount': 1});
      }
    });
  }

  /// Firestore에서 히스토리 조회 (다른 유저가 수집한 데이터도 포함)
  Future<List<KeywordPriceSummary>> getHistory(String keyword) async {
    final normalized = _normalizeKeyword(keyword);
    final cacheKey = 'kph_$normalized';
    final cached = _cache.get<List<KeywordPriceSummary>>(cacheKey);
    if (cached != null) return cached;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('keyword_snapshots')
          .doc(normalized)
          .get();

      if (!doc.exists) return [];

      final snapshots = (doc.data()?['snapshots'] as List<dynamic>?) ?? [];
      final result = snapshots
          .map((s) =>
              KeywordPriceSummary.fromJson(Map<String, dynamic>.from(s as Map)))
          .toList();

      _cache.put(cacheKey, result);
      return result;
    } catch (e) {
      debugPrint('[KeywordTracker] getHistory error: $e');
      // 에러 시 빈 리스트 캐시 → 동일 키워드 재호출 방지
      _cache.put(cacheKey, <KeywordPriceSummary>[]);
      return [];
    }
  }

  /// trackerCount 증가
  Future<void> incrementTracker(String keyword) async {
    final normalized = _normalizeKeyword(keyword);
    final docRef = FirebaseFirestore.instance
        .collection('keyword_snapshots')
        .doc(normalized);

    await docRef.set({
      'trackerCount': FieldValue.increment(1),
      'lastCollectedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// trackerCount 감소
  Future<void> decrementTracker(String keyword) async {
    final normalized = _normalizeKeyword(keyword);
    final docRef = FirebaseFirestore.instance
        .collection('keyword_snapshots')
        .doc(normalized);

    await docRef.set({
      'trackerCount': FieldValue.increment(-1),
    }, SetOptions(merge: true));
  }

  /// 키워드 정규화 (Firestore 문서 ID용)
  String _normalizeKeyword(String keyword) {
    return keyword
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[/\.#\$\[\]]'), '')
        .replaceAll(RegExp(r'\s+'), '_');
  }

  Future<Box<dynamic>> _openMetaBox() => getOrOpenBox<dynamic>(_metaBoxName);
}
