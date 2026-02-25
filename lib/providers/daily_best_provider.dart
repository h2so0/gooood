import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/product.dart';

final dailyBestProvider = FutureProvider<List<Product>>((ref) async {
  // 1) cache/dailyBest 먼저 확인
  final doc = await FirebaseFirestore.instance
      .collection('cache')
      .doc('dailyBest')
      .get();
  if (doc.exists) {
    final items = (doc.data()?['items'] as List?) ?? [];
    if (items.isNotEmpty) {
      return items
          .map((e) => Product.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
  }

  // 2) cache 없으면 Firestore에서 가져와서 판매처별 2개씩 점수화 순위
  final snap = await FirebaseFirestore.instance
      .collection('products')
      .orderBy('reviewScore', descending: true)
      .limit(100)
      .get();
  final all = snap.docs.map((d) => Product.fromJson(d.data())).toList();
  return _rankByMall(all);
});

/// 종합 점수 산출 (리뷰 점수 + 리뷰 수 + 할인율 + 구매 수)
double calcBestScore(Product p) => _calcScore(p);

double _calcScore(Product p) {
  final review = (p.reviewScore ?? 0) * 20;       // 0~100
  final reviewPop = (p.reviewCount ?? 0).clamp(0, 500) / 5; // 0~100
  final drop = p.dropRate.clamp(0, 100);           // 0~100
  final purchase = (p.purchaseCount ?? 0).clamp(0, 1000) / 10; // 0~100
  return review * 0.3 + reviewPop * 0.25 + drop * 0.25 + purchase * 0.2;
}

/// 판매처별 2개씩 선정 후 점수 내림차순 정렬
List<Product> _rankByMall(List<Product> products) {
  // 점수 내림차순 정렬
  final scored = [...products]..sort((a, b) => _calcScore(b).compareTo(_calcScore(a)));

  final mallCount = <String, int>{};
  final picked = <Product>[];

  for (final p in scored) {
    final mall = p.displayMallName;
    final count = mallCount[mall] ?? 0;
    if (count < 2) {
      picked.add(p);
      mallCount[mall] = count + 1;
    }
    if (picked.length >= 10) break; // 최대 10개
  }

  // 최종 점수순 정렬
  picked.sort((a, b) => _calcScore(b).compareTo(_calcScore(a)));
  return picked;
}
