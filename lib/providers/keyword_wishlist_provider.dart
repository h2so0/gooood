import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../constants/app_constants.dart';
import '../models/keyword_wishlist.dart';
import '../services/analytics_service.dart';
import '../services/device_profile_sync.dart';
import '../services/keyword_price_tracker.dart';
import 'keyword_price_provider.dart';

const _maxWishlistCount = 20;

class KeywordWishlistNotifier extends StateNotifier<List<KeywordWishItem>> {
  final KeywordPriceTracker _tracker;

  KeywordWishlistNotifier(this._tracker) : super([]) {
    _load();
  }

  Future<void> _load() async {
    try {
      final box = await _openBox();
      final items = <KeywordWishItem>[];
      for (final key in box.keys) {
        final raw = box.get(key);
        if (raw != null) {
          items.add(
              KeywordWishItem.fromJson(jsonDecode(raw) as Map<String, dynamic>));
        }
      }
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      state = items;
    } catch (e) {
      debugPrint('[KeywordWishlist] load error: $e');
    }
  }

  Future<bool> add(String keyword, {String? category}) async {
    if (state.length >= _maxWishlistCount) return false;
    if (state.any((i) => i.keyword == keyword)) return false;

    final item = KeywordWishItem(
      keyword: keyword,
      createdAt: DateTime.now(),
      category: category,
    );

    state = [item, ...state];
    await _save();
    AnalyticsService.setWishlistCountProperty(state.length);
    DeviceProfileSync().scheduleSync();

    try {
      await _tracker.incrementTracker(keyword);
    } catch (e) {
      debugPrint('[KeywordWishlist] incrementTracker error: $e');
    }

    return true;
  }

  Future<void> remove(String keyword) async {
    state = state.where((i) => i.keyword != keyword).toList();
    await _save();
    AnalyticsService.setWishlistCountProperty(state.length);
    DeviceProfileSync().scheduleSync();

    try {
      await _tracker.decrementTracker(keyword);
    } catch (e) {
      debugPrint('[KeywordWishlist] decrementTracker error: $e');
    }
  }

  Future<void> updateTargetPrice(String keyword, int? targetPrice) async {
    state = state.map((item) {
      if (item.keyword == keyword) {
        return item.copyWith(
          targetPrice: targetPrice,
          clearTargetPrice: targetPrice == null,
        );
      }
      return item;
    }).toList();
    await _save();
    DeviceProfileSync().scheduleSync();
  }

  Future<void> _save() async {
    final box = await _openBox();
    await box.clear();
    for (final item in state) {
      await box.put(item.keyword, jsonEncode(item.toJson()));
    }
  }

  Future<Box<String>> _openBox() async {
    const name = HiveBoxes.keywordWishlist;
    if (Hive.isBoxOpen(name)) return Hive.box<String>(name);
    return Hive.openBox<String>(name);
  }
}

final keywordWishlistProvider =
    StateNotifierProvider<KeywordWishlistNotifier, List<KeywordWishItem>>(
        (ref) {
  final tracker = ref.watch(keywordPriceTrackerProvider);
  return KeywordWishlistNotifier(tracker);
});

final isKeywordWishlistedProvider =
    Provider.family<bool, String>((ref, keyword) {
  final list = ref.watch(keywordWishlistProvider);
  return list.any((i) => i.keyword == keyword);
});
