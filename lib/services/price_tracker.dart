import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'naver_shopping_api.dart';

/// 로컬 DB에 상품 가격 이력 축적
class PriceTracker {
  static const _boxName = 'price_history';
  static const _metaBoxName = 'tracker_meta';

  late Box<Map> _historyBox;
  late Box _metaBox;
  final NaverShoppingApi _api;

  PriceTracker(this._api);

  Future<void> init() async {
    _historyBox = await Hive.openBox<Map>(_boxName);
    _metaBox = await Hive.openBox(_metaBoxName);
  }

  /// 인기 상품 가격을 수집해서 로컬에 저장
  Future<void> collectPrices(List<String> keywords) async {
    final now = DateTime.now();
    final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // 하루에 한 번만 수집
    final lastCollect = _metaBox.get('lastCollectDate', defaultValue: '');
    if (lastCollect == today) return;

    for (final keyword in keywords) {
      try {
        final products = await _api.search(
            query: keyword, display: 5, sort: 'sim');

        for (final p in products) {
          if (p.id.isEmpty) continue;

          final existing =
              _historyBox.get(p.id)?.cast<String, dynamic>() ?? {};
          final history = (existing['prices'] as List?)
                  ?.cast<Map>()
                  .map((m) => m.cast<String, dynamic>())
                  .toList() ??
              <Map<String, dynamic>>[];

          // 오늘 데이터가 없으면 추가
          if (!history.any((h) => h['date'] == today)) {
            history.add({
              'date': today,
              'price': p.currentPrice,
            });
          }

          // 최근 90일만 유지
          if (history.length > 90) {
            history.removeRange(0, history.length - 90);
          }

          await _historyBox.put(p.id, {
            'id': p.id,
            'title': p.title,
            'imageUrl': p.imageUrl,
            'mallName': p.mallName,
            'brand': p.brand ?? '',
            'category1': p.category1,
            'link': p.link,
            'prices': history,
            'updatedAt': today,
          });
        }
      } catch (e) {
        debugPrint('[PriceTracker] keyword "$keyword" error: $e');
      }
    }

    await _metaBox.put('lastCollectDate', today);
  }

  /// 특정 상품의 가격 이력 조회
  List<PriceRecord> getHistory(String productId) {
    final data = _historyBox.get(productId)?.cast<String, dynamic>();
    if (data == null) return [];

    final prices = (data['prices'] as List?)
            ?.cast<Map>()
            .map((m) => m.cast<String, dynamic>())
            .toList() ??
        [];

    return prices.map((h) {
      return PriceRecord(
        date: DateTime.tryParse(h['date'] ?? '') ?? DateTime.now(),
        price: (h['price'] as num?)?.toInt() ?? 0,
      );
    }).toList();
  }

  /// 가격 변동이 큰 상품 찾기 (축적된 데이터 기반)
  List<TrackedProduct> getDroppedProducts({int days = 7}) {
    final results = <TrackedProduct>[];
    final cutoff = DateTime.now().subtract(Duration(days: days));

    for (final key in _historyBox.keys) {
      final data = _historyBox.get(key)?.cast<String, dynamic>();
      if (data == null) continue;

      final prices = (data['prices'] as List?)
              ?.cast<Map>()
              .map((m) => m.cast<String, dynamic>())
              .toList() ??
          [];

      if (prices.length < 2) continue;

      final recent = prices.where((h) {
        final d = DateTime.tryParse(h['date'] ?? '');
        return d != null && d.isAfter(cutoff);
      }).toList();

      if (recent.isEmpty) continue;

      final currentPrice = (prices.last['price'] as num).toInt();
      final oldPrice = (recent.first['price'] as num).toInt();

      if (oldPrice > currentPrice && oldPrice > 0) {
        final dropRate = ((oldPrice - currentPrice) / oldPrice) * 100;
        if (dropRate >= 3) {
          results.add(TrackedProduct(
            id: data['id'] ?? '',
            title: data['title'] ?? '',
            imageUrl: data['imageUrl'] ?? '',
            mallName: data['mallName'] ?? '',
            link: data['link'] ?? '',
            currentPrice: currentPrice,
            previousPrice: oldPrice,
            dropRate: dropRate,
            category1: data['category1'] ?? '',
          ));
        }
      }
    }

    results.sort((a, b) => b.dropRate.compareTo(a.dropRate));
    return results;
  }

  /// 축적된 총 상품 수
  int get trackedCount => _historyBox.length;
}

class PriceRecord {
  final DateTime date;
  final int price;
  const PriceRecord({required this.date, required this.price});
}

class TrackedProduct {
  final String id;
  final String title;
  final String imageUrl;
  final String mallName;
  final String link;
  final int currentPrice;
  final int previousPrice;
  final double dropRate;
  final String category1;

  const TrackedProduct({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.mallName,
    required this.link,
    required this.currentPrice,
    required this.previousPrice,
    required this.dropRate,
    required this.category1,
  });
}
