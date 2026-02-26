import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import '../models/keyword_wishlist.dart';
import '../providers/viewed_products_provider.dart';

class DeviceProfileSync {
  DeviceProfileSync._();
  static final DeviceProfileSync _instance = DeviceProfileSync._();
  factory DeviceProfileSync() => _instance;

  static const _syncIntervalMs = 6 * 60 * 60 * 1000; // 6 hours
  static const _debounceMs = 30 * 1000; // 30 seconds
  static const _maxWatchedProducts = 30;
  static const _lastSyncKey = 'device_profile_last_sync';
  static const _viewedBoxName = 'viewed_products';
  static const _keywordWishlistBoxName = HiveBoxes.keywordWishlist;

  final _messaging = FirebaseMessaging.instance;
  final _db = FirebaseFirestore.instance;

  Timer? _debounceTimer;
  // ignore: unused_field — stored to prevent GC of the subscription
  StreamSubscription<String>? _tokenRefreshSub;
  String? _currentTokenHash;
  bool _initialized = false;

  /// Call once at app startup (after NotificationService.initialize)
  Future<void> initialize() async {
    if (kIsWeb || _initialized) return;
    _initialized = true;

    try {
      final token = await _messaging.getToken();
      if (token != null) {
        _currentTokenHash = _hashToken(token);
        await _syncIfNeeded();
      }

      // Listen for token refresh → migrate old profile to new doc
      _tokenRefreshSub = _messaging.onTokenRefresh.listen((newToken) async {
        final oldHash = _currentTokenHash;
        final newHash = _hashToken(newToken);
        if (oldHash != null && oldHash != newHash) {
          await _migrateProfile(oldHash, newHash, newToken);
        }
        _currentTokenHash = newHash;
      });
    } catch (e) {
      debugPrint('[DeviceProfileSync] initialize error: $e');
    }
  }

  /// Schedule a debounced sync (called when viewed products change)
  void scheduleSync() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(
      const Duration(milliseconds: _debounceMs),
      () => _syncIfNeeded(),
    );
  }

  /// Force immediate sync (called on settings change)
  Future<void> syncNow() async {
    _debounceTimer?.cancel();
    await _performSync();
  }

  Future<void> _syncIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSync = prefs.getInt(_lastSyncKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (now - lastSync >= _syncIntervalMs) {
      await _performSync();
    }
  }

  Future<void> _performSync() async {
    if (kIsWeb) return;

    try {
      final token = await _messaging.getToken();
      if (token == null) return;

      final tokenHash = _hashToken(token);
      _currentTokenHash = tokenHash;

      final prefs = await SharedPreferences.getInstance();

      // Build watched product list + category scores + price snapshots
      final viewedEntries = await _loadViewedEntries();
      final watchedProductIds = <String>[];
      final categoryScores = <String, double>{};
      final subCategoryScores = <String, double>{};
      final priceSnapshots = <String, int>{};

      final now = DateTime.now();

      for (final entry in viewedEntries.take(_maxWatchedProducts)) {
        final product = entry.product;
        final docId = product.id;
        watchedProductIds.add(docId);

        // Price snapshot
        if (product.currentPrice > 0) {
          priceSnapshots[docId] = product.currentPrice;
        }

        // Recency weight for category scoring
        final daysDiff = now.difference(entry.viewedAt).inDays;
        double weight;
        if (daysDiff == 0) {
          weight = 3.0;
        } else if (daysDiff == 1) {
          weight = 2.0;
        } else if (daysDiff <= 7) {
          weight = 1.5;
        } else {
          weight = 1.0;
        }

        // Category scoring
        final cat = product.category1;
        if (cat.isNotEmpty) {
          categoryScores[cat] = (categoryScores[cat] ?? 0) + weight;
        }
        final subCat = product.subCategory;
        if (subCat != null && subCat.isNotEmpty) {
          subCategoryScores[subCat] =
              (subCategoryScores[subCat] ?? 0) + weight;
        }
      }

      // Keyword wishlist
      final keywordWishItems = await _loadKeywordWishlist();
      final keywordWishlist = keywordWishItems
          .where((item) => item.targetPrice != null)
          .map((item) => <String, dynamic>{
                'keyword': item.keyword,
                'targetPrice': item.targetPrice,
                'category': item.category,
              })
          .toList();

      // Notification settings
      final enablePriceDrop = prefs.getBool('noti_priceDrop') ?? true;
      final enableCategoryAlert = prefs.getBool('noti_categoryAlert') ?? true;
      final enableSmartDigest = prefs.getBool('noti_smartDigest') ?? false;
      final quietStart = prefs.getInt('noti_quietStart') ?? 22;
      final quietEnd = prefs.getInt('noti_quietEnd') ?? 8;

      final profile = {
        'fcmToken': token,
        'tokenHash': tokenHash,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'watchedProductIds': watchedProductIds,
        'categoryScores': categoryScores,
        'subCategoryScores': subCategoryScores,
        'priceSnapshots': priceSnapshots,
        'keywordWishlist': keywordWishlist,
        'enablePriceDrop': enablePriceDrop,
        'enableCategoryAlert': enableCategoryAlert,
        'enableSmartDigest': enableSmartDigest,
        'quietStartHour': quietStart,
        'quietEndHour': quietEnd,
        'lastSyncedAt': FieldValue.serverTimestamp(),
      };

      await _db
          .collection('device_profiles')
          .doc(tokenHash)
          .set(profile, SetOptions(merge: true));

      // Record sync time
      await prefs.setInt(
          _lastSyncKey, DateTime.now().millisecondsSinceEpoch);

      debugPrint(
          '[DeviceProfileSync] synced: ${watchedProductIds.length} products, '
          '${categoryScores.length} categories');
    } catch (e) {
      debugPrint('[DeviceProfileSync] sync error: $e');
    }
  }

  /// 클라이언트가 쓸 수 있는 필드만 (서버 전용 필드 제외)
  static const _clientFields = {
    'fcmToken', 'tokenHash', 'platform',
    'watchedProductIds', 'categoryScores', 'subCategoryScores',
    'priceSnapshots', 'keywordWishlist',
    'enablePriceDrop', 'enableCategoryAlert', 'enableSmartDigest',
    'quietStartHour', 'quietEndHour', 'lastSyncedAt',
  };

  Future<void> _migrateProfile(
      String oldHash, String newHash, String newToken) async {
    try {
      // 마이그레이션: 새 토큰으로 즉시 sync (기존 문서 읽기 불가하므로)
      // 서버 필드(lastPriceDropSentAt 등)는 소실되지만 다음 알림 주기에 재생성됨
      _currentTokenHash = newHash;
      await _performSync();
      debugPrint('[DeviceProfileSync] migrated to new token $newHash');
    } catch (e) {
      debugPrint('[DeviceProfileSync] migration error: $e');
    }
  }

  List<ViewedProductEntry> _loadViewedEntriesSync() {
    try {
      if (!Hive.isBoxOpen(_viewedBoxName)) return [];
      final box = Hive.box<String>(_viewedBoxName);
      final entries = <ViewedProductEntry>[];
      for (final key in box.keys) {
        try {
          final json = jsonDecode(box.get(key)!) as Map<String, dynamic>;
          entries.add(ViewedProductEntry.fromJson(json));
        } catch (e) { debugPrint('[DeviceProfileSync] parse entry error: $e'); }
      }
      entries.sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
      return entries;
    } catch (e) {
      debugPrint('[DeviceProfileSync] loadViewedEntriesSync error: $e');
      return [];
    }
  }

  Future<List<ViewedProductEntry>> _loadViewedEntries() async {
    try {
      if (!Hive.isBoxOpen(_viewedBoxName)) {
        await Hive.openBox<String>(_viewedBoxName);
      }
      return _loadViewedEntriesSync();
    } catch (e) {
      debugPrint('[DeviceProfileSync] loadViewedEntries error: $e');
      return [];
    }
  }

  Future<List<KeywordWishItem>> _loadKeywordWishlist() async {
    try {
      final boxName = _keywordWishlistBoxName;
      if (!Hive.isBoxOpen(boxName)) {
        await Hive.openBox<String>(boxName);
      }
      final box = Hive.box<String>(boxName);
      final items = <KeywordWishItem>[];
      for (final key in box.keys) {
        try {
          final raw = box.get(key);
          if (raw != null) {
            items.add(KeywordWishItem.fromJson(
                jsonDecode(raw) as Map<String, dynamic>));
          }
        } catch (e) {
          debugPrint('[DeviceProfileSync] parse keyword wishlist error: $e');
        }
      }
      return items;
    } catch (e) {
      debugPrint('[DeviceProfileSync] loadKeywordWishlist error: $e');
      return [];
    }
  }

  String _hashToken(String token) {
    return sha256.convert(utf8.encode(token)).toString();
  }
}
