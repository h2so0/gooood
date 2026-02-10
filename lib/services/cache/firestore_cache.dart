import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../models/product.dart';
import 'memory_cache.dart';

/// Firestore 캐시 읽기 헬퍼
Future<List<T>?> firestoreList<T>(
  String docId,
  T Function(Map<String, dynamic>) fromJson,
) async {
  try {
    final doc = await FirebaseFirestore.instance
        .collection('cache')
        .doc(docId)
        .get();
    if (!doc.exists) return null;
    final items = (doc.data()?['items'] as List<dynamic>?) ?? [];
    if (items.isEmpty) return null;
    return items
        .map((e) => fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  } catch (e) {
    debugPrint('[Cache] Firestore read $docId error: $e');
    return null;
  }
}

/// Firestore 캐시 → 메모리 캐시 통합 상품 조회
Future<List<Product>> fetchCachedProducts(
  String key,
  MemoryCache cache,
) async {
  final cached = cache.get<List<Product>>(key);
  if (cached != null) return cached;

  final firestore = await firestoreList<Product>(key, Product.fromJson);
  if (firestore != null) {
    cache.put(key, firestore);
    return firestore;
  }
  return [];
}
