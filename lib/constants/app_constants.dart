/// Firestore cache document IDs
class CacheKeys {
  static const todayDeals = 'todayDeals';
  static const shoppingLive = 'shoppingLive';
  static const naverPromotions = 'naverPromotions';
  static const st11Deals = '11stDeals';
  static const gmarketDeals = 'gmarketDeals';
  static const auctionDeals = 'auctionDeals';
  static const keywordRank = 'keywordRank';

  static String best100(String categoryId) => 'best100_$categoryId';
  static String popularKeywords(String categoryId) =>
      'popularKeywords_$categoryId';
  static const popularKeywordsAll = 'popularKeywords_all';
}

/// Hive box names
class HiveBoxes {
  static const priceHistory = 'price_history';
  static const trackerMeta = 'tracker_meta';
  static const notificationHistory = 'notification_history';
}

/// Cache durations
class CacheDurations {
  static const standard = Duration(minutes: 30);
}
