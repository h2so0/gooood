/// Firestore cache document IDs
class CacheKeys {
  static const keywordRank = 'keywordRank';

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
