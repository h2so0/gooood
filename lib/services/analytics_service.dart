import 'package:firebase_analytics/firebase_analytics.dart';
import '../models/product.dart';

class AnalyticsService {
  static final _analytics = FirebaseAnalytics.instance;

  // ── helpers ──

  static Map<String, Object> _productParams(Product p) => {
        'product_id': p.id,
        'price': p.currentPrice,
        'category': p.category1,
        'mall_name': p.mallName,
        'drop_rate': p.dropRate.toStringAsFixed(1),
        if (p.badge != null) 'badge': p.badge!.name,
      };

  static String _source(Product p) {
    final b = p.badge;
    if (b != null) return b.shortLabel;
    return 'unknown';
  }

  // ── product events ──

  static Future<void> logProductViewed(Product p) =>
      _analytics.logEvent(name: 'product_viewed', parameters: {
        ..._productParams(p),
        'source': _source(p),
      });

  static Future<void> logPurchaseIntent(Product p) =>
      _analytics.logEvent(name: 'purchase_intent', parameters: {
        ..._productParams(p),
        'source': _source(p),
      });

  static Future<void> logProductShared(Product p) =>
      _analytics.logEvent(name: 'product_shared', parameters: {
        'product_id': p.id,
        'price': p.currentPrice,
        'category': p.category1,
        'mall_name': p.mallName,
      });

  // ── search / browse ──

  static Future<void> logSearch(String query) =>
      _analytics.logEvent(name: 'search_performed', parameters: {
        'query': query,
      });

  static Future<void> logTrendingKeywordTap(String keyword, {int? rank}) =>
      _analytics.logEvent(name: 'trending_keyword_tap', parameters: {
        'keyword': keyword,
        if (rank != null) 'rank': rank,
      });

  static Future<void> logCategoryChanged(String category) =>
      _analytics.logEvent(name: 'category_changed', parameters: {
        'category': category,
      });

  static Future<void> logSubCategoryFilter(
          String category, String? subCategory) =>
      _analytics.logEvent(name: 'sub_category_filter', parameters: {
        'category': category,
        'sub_category': subCategory ?? 'all',
      });

  // ── wishlist ──

  static Future<void> logKeywordWishlistAdd(String keyword) =>
      _analytics.logEvent(name: 'keyword_wishlist_add', parameters: {
        'keyword': keyword,
      });

  static Future<void> logKeywordWishlistRemove(String keyword) =>
      _analytics.logEvent(name: 'keyword_wishlist_remove', parameters: {
        'keyword': keyword,
      });

  static Future<void> logTargetPriceSet(
          String keyword, int targetPrice, int? currentMinPrice) =>
      _analytics.logEvent(name: 'target_price_set', parameters: {
        'keyword': keyword,
        'target_price': targetPrice,
        if (currentMinPrice != null) 'current_min_price': currentMinPrice,
      });

  static Future<void> logTargetPriceCleared(String keyword) =>
      _analytics.logEvent(name: 'target_price_cleared', parameters: {
        'keyword': keyword,
      });

  // ── notification / deeplink ──

  static Future<void> logNotificationToggle(String setting, bool enabled) =>
      _analytics.logEvent(name: 'notification_toggle', parameters: {
        'setting': setting,
        'enabled': enabled.toString(),
      });

  static Future<void> logNotificationTap(String? productId) =>
      _analytics.logEvent(name: 'notification_tap', parameters: {
        if (productId != null) 'product_id': productId,
      });

  static Future<void> logDeepLinkOpened(String productId) =>
      _analytics.logEvent(name: 'deep_link_opened', parameters: {
        'product_id': productId,
      });

  // ── settings ──

  static Future<void> logThemeToggle(bool isDark) =>
      _analytics.logEvent(name: 'theme_toggle', parameters: {
        'theme': isDark ? 'dark' : 'light',
      });

  // ── user properties ──

  static Future<void> setThemeProperty(bool isDark) =>
      _analytics.setUserProperty(
        name: 'theme_preference',
        value: isDark ? 'dark' : 'light',
      );

  static Future<void> setWishlistCountProperty(int count) =>
      _analytics.setUserProperty(
        name: 'wishlist_count',
        value: count.toString(),
      );

  static Future<void> setNotiHotDealProperty(bool enabled) =>
      _analytics.setUserProperty(
        name: 'noti_hot_deal',
        value: enabled ? 'on' : 'off',
      );
}
