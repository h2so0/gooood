import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/device_profile_sync.dart';

class AdminStats {
  final DateTime? updatedAt;
  final int totalUsers;
  final int iosUsers;
  final int androidUsers;
  final int activeToday;
  final int active7d;
  final int active30d;
  final int totalProducts;
  final Map<String, int> productsBySource;
  final Map<String, int> productsByCategory;
  final int notificationsLast24h;
  final Map<String, int> notificationsByType;
  final int wishlistTotalItems;
  final List<Map<String, dynamic>> topKeywords;
  final Map<String, dynamic> banners;

  const AdminStats({
    this.updatedAt,
    this.totalUsers = 0,
    this.iosUsers = 0,
    this.androidUsers = 0,
    this.activeToday = 0,
    this.active7d = 0,
    this.active30d = 0,
    this.totalProducts = 0,
    this.productsBySource = const {},
    this.productsByCategory = const {},
    this.notificationsLast24h = 0,
    this.notificationsByType = const {},
    this.wishlistTotalItems = 0,
    this.topKeywords = const [],
    this.banners = const {},
  });

  factory AdminStats.fromJson(Map<String, dynamic> json) {
    final users = json['users'] as Map<String, dynamic>? ?? {};
    final products = json['products'] as Map<String, dynamic>? ?? {};
    final notifications = json['notifications'] as Map<String, dynamic>? ?? {};
    final wishlist = json['wishlist'] as Map<String, dynamic>? ?? {};

    return AdminStats(
      updatedAt: (json['updatedAt'] as Timestamp?)?.toDate(),
      totalUsers: (users['total'] as num?)?.toInt() ?? 0,
      iosUsers: (users['ios'] as num?)?.toInt() ?? 0,
      androidUsers: (users['android'] as num?)?.toInt() ?? 0,
      activeToday: (users['activeToday'] as num?)?.toInt() ?? 0,
      active7d: (users['active7d'] as num?)?.toInt() ?? 0,
      active30d: (users['active30d'] as num?)?.toInt() ?? 0,
      totalProducts: (products['total'] as num?)?.toInt() ?? 0,
      productsBySource: _toIntMap(products['bySource']),
      productsByCategory: _toIntMap(products['byCategory']),
      notificationsLast24h: (notifications['last24h'] as num?)?.toInt() ?? 0,
      notificationsByType: _toIntMap(notifications['byType']),
      wishlistTotalItems: (wishlist['totalItems'] as num?)?.toInt() ?? 0,
      topKeywords: (wishlist['topKeywords'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
      banners: Map<String, dynamic>.from(json['banners'] as Map? ?? {}),
    );
  }

  static Map<String, int> _toIntMap(dynamic raw) {
    if (raw is! Map) return {};
    return Map.fromEntries(
      (raw as Map<String, dynamic>)
          .entries
          .map((e) => MapEntry(e.key, (e.value as num?)?.toInt() ?? 0)),
    );
  }
}

final adminStatsProvider = FutureProvider.autoDispose<AdminStats>((ref) async {
  final doc = await FirebaseFirestore.instance
      .collection('cache')
      .doc('admin_stats')
      .get();

  if (!doc.exists || doc.data() == null) {
    return const AdminStats();
  }
  return AdminStats.fromJson(doc.data()!);
});

final isAdminProvider = FutureProvider<bool>((ref) async {
  final myHash = DeviceProfileSync().tokenHash;
  if (myHash == null) return false;

  final doc = await FirebaseFirestore.instance
      .collection('cache')
      .doc('admin_config')
      .get();

  if (!doc.exists || doc.data() == null) return false;
  return doc.data()!['adminTokenHash'] == myHash;
});
