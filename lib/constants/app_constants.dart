/// 네이버 쇼핑 카테고리 코드 (단일 소스)
const shoppingCategoryIds = <String, String>{
  '디지털/가전': '50000003',
  '패션의류': '50000000',
  '화장품/미용': '50000002',
  '생활/건강': '50000008',
  '식품': '50000006',
  '스포츠/레저': '50000007',
  '출산/육아': '50000005',
  '패션잡화': '50000001',
  '가구/인테리어': '50000004',
};

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
  static const keywordWishlist = 'keyword_wishlist';
  static const keywordTrackerMeta = 'keyword_tracker_meta';
}

/// Sub-category mapping (shared between backend & frontend)
const subCategories = <String, List<String>>{
  '디지털/가전': ['스마트폰/태블릿', '노트북/PC', 'TV/영상가전', '생활가전', '음향/게임'],
  '패션/의류': ['여성의류', '남성의류', '신발/가방', '시계/주얼리', '언더웨어/잠옷'],
  '생활/건강': ['가구/인테리어', '주방용품', '생활용품', '건강식품/비타민', '반려동물'],
  '식품': ['신선식품', '가공식품', '음료/커피', '건강식품', '간식/베이커리'],
  '뷰티': ['스킨케어', '메이크업', '헤어/바디', '향수', '남성뷰티'],
  '스포츠/레저': ['운동복/신발', '헬스/요가', '아웃도어/캠핑', '골프', '자전거/킥보드'],
  '출산/육아': ['유아동복', '기저귀/물티슈', '분유/이유식', '장난감/완구', '유모차/카시트'],
};

/// Cache durations
class CacheDurations {
  static const standard = Duration(minutes: 30);
}

/// API / Network
class ApiConfig {
  static const timeout = Duration(seconds: 10);
  static const maxRetries = 3;
  static const searchDisplay = 40;
  static const priceCompareDisplay = 100;
}

/// Pagination
class PaginationConfig {
  static const pageSize = 20;
  static const scrollThreshold = 500.0;
}

/// Review prompt thresholds
class ReviewConfig {
  static const minDaysSinceInstall = 3;
  static const minViewCount = 5;
  static const cooldownDays = 90;
}

/// Limits
class AppLimits {
  static const maxWishlistCount = 20;
  static const maxViewedProducts = 50;
  static const maxNotificationHistory = 100;
  static const maxMemoryCacheEntries = 50;
}
