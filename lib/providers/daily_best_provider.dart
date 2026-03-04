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

  // 2) cache 없으면 Firestore에서 전체 소스 인기 상품 가져와서 점수화
  final results = await Future.wait([
    // 실구매수 높은 상품 (전체 소스)
    FirebaseFirestore.instance
        .collection('products')
        .where('purchaseCount', isGreaterThan: 0)
        .orderBy('purchaseCount', descending: true)
        .limit(80)
        .get(),
    // 리뷰 많은 상품 (전체 소스)
    FirebaseFirestore.instance
        .collection('products')
        .where('reviewCount', isGreaterThan: 10)
        .orderBy('reviewCount', descending: true)
        .limit(80)
        .get(),
    // 피드 인기순 (전체 소스)
    FirebaseFirestore.instance
        .collection('products')
        .orderBy('feedOrder')
        .limit(60)
        .get(),
  ]);
  final seen = <String>{};
  final all = <Product>[];
  for (final snap in results) {
    for (final d in snap.docs) {
      if (seen.add(d.id)) {
        all.add(Product.fromJson(d.data()));
      }
    }
  }
  return _rankByMall(all);
});

/// 종합 점수 산출 (실시간 인기 중심: 순위 + 구매수 + 리뷰수)
double calcBestScore(Product p) => _calcScore(p);

double _calcScore(Product p) {
  final purchase = (p.purchaseCount ?? 0).clamp(0, 1000) / 10; // 0~100
  final reviewPop = (p.reviewCount ?? 0).clamp(0, 500) / 5;    // 0~100
  final review = (p.reviewScore ?? 0) * 20;                     // 0~100
  final rankBonus = p.rank != null ? (100 - p.rank!).clamp(0, 100).toDouble() : 0.0;
  final drop = p.dropRate.clamp(0, 50).toDouble();              // 0~50

  return purchase * 0.35 +      // 35% 실구매수
         reviewPop * 0.25 +     // 25% 리뷰수 (구매 활발도)
         review * 0.15 +        // 15% 리뷰 품질
         rankBonus * 0.15 +     // 15% 순위 보너스 (best100만)
         drop * 0.10;           // 10% 할인 보너스
}

/// 판매처별 2개씩 선정 후 점수 내림차순 정렬
List<Product> _rankByMall(List<Product> products) {
  // 점수 내림차순 정렬
  final scored = [...products]..sort((a, b) => _calcScore(b).compareTo(_calcScore(a)));

  final mallCount = <String, int>{};
  final picked = <Product>[];

  // 1차: 판매처별 2개씩
  for (final p in scored) {
    if (picked.length >= 10) break;
    final mall = p.displayMallName;
    final count = mallCount[mall] ?? 0;
    if (count < 2) {
      picked.add(p);
      mallCount[mall] = count + 1;
    }
  }

  // 부족하면 나머지에서 채움 (판매처 제한 해제)
  if (picked.length < 10) {
    final pickedIds = picked.map((p) => p.id).toSet();
    for (final p in scored) {
      if (picked.length >= 10) break;
      if (!pickedIds.contains(p.id)) {
        picked.add(p);
      }
    }
  }

  // 최종 점수순 정렬
  picked.sort((a, b) => _calcScore(b).compareTo(_calcScore(a)));
  return picked;
}
