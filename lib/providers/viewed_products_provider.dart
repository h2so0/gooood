import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/product.dart';
import '../services/device_profile_sync.dart';
import '../utils/hive_helper.dart';

class ViewedProductEntry {
  final Product product;
  final DateTime viewedAt;

  ViewedProductEntry({required this.product, required this.viewedAt});

  Map<String, dynamic> toJson() => {
        'product': product.toJson(),
        'viewedAt': viewedAt.toIso8601String(),
      };

  factory ViewedProductEntry.fromJson(Map<String, dynamic> json) =>
      ViewedProductEntry(
        product: Product.fromJson(json['product']),
        viewedAt: DateTime.parse(json['viewedAt']),
      );

  bool get isExpired {
    final end = product.saleEndDate;
    if (end == null) return false;
    try {
      return DateTime.parse(end).isBefore(DateTime.now());
    } catch (e) {
      debugPrint('[ViewedProducts] date parse error: $e');
      return false;
    }
  }
}

final viewedProductsProvider =
    StateNotifierProvider<ViewedProductsNotifier, List<ViewedProductEntry>>(
        (ref) {
  return ViewedProductsNotifier();
});

class ViewedProductsNotifier extends StateNotifier<List<ViewedProductEntry>> {
  static const _boxName = 'viewed_products';
  Future<void>? _saveFuture;

  ViewedProductsNotifier() : super([]) {
    _load();
  }

  Future<Box<String>> _openBox() => getOrOpenBox<String>(_boxName);

  Future<void> _load() async {
    final box = await _openBox();
    final entries = <ViewedProductEntry>[];
    for (final key in box.keys) {
      try {
        final json = jsonDecode(box.get(key)!) as Map<String, dynamic>;
        entries.add(ViewedProductEntry.fromJson(json));
      } catch (e) { debugPrint('[ViewedProducts] load entry error: $e'); }
    }
    entries.sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
    state = entries.take(50).toList();
  }

  Future<void> _save() {
    // Chain saves to prevent concurrent Hive writes
    _saveFuture = (_saveFuture ?? Future.value()).then((_) async {
      try {
        final box = await _openBox();
        await box.clear();
        for (final entry in state) {
          await box.put(entry.product.id, jsonEncode(entry.toJson()));
        }
      } catch (e) {
        debugPrint('[ViewedProducts] _save error: $e');
      }
    });
    return _saveFuture!;
  }

  void add(Product product) {
    final entry = ViewedProductEntry(
      product: product,
      viewedAt: DateTime.now(),
    );
    state = [
      entry,
      ...state.where((e) => e.product.id != product.id),
    ].take(50).toList();
    _save();
    DeviceProfileSync().scheduleSync();
  }

  void remove(String productId) {
    state = state.where((e) => e.product.id != productId).toList();
    _save();
  }

  void clearAll() {
    state = [];
    _save();
  }
}
