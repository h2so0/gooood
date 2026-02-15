import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../constants/app_constants.dart';

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

class CacheEntry<T> {
  final T data;
  final DateTime createdAt;
  CacheEntry(this.data) : createdAt = DateTime.now();
  bool get isExpired =>
      DateTime.now().difference(createdAt) > CacheDurations.standard;
}

class MemoryCache {
  static const _maxEntries = 50;
  final Map<String, CacheEntry<dynamic>> _store = {};

  T? get<T>(String key) {
    final entry = _store[key];
    if (entry != null && !entry.isExpired) return entry.data as T;
    return null;
  }

  void put<T>(String key, T data) {
    _store[key] = CacheEntry<T>(data);
    if (_store.length > _maxEntries) {
      final oldest = _store.entries.reduce(
        (a, b) => a.value.createdAt.isBefore(b.value.createdAt) ? a : b,
      );
      _store.remove(oldest.key);
    }
  }

  void clear() => _store.clear();
}
