import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/product.dart';
import '../services/naver_shopping_api.dart';
import '../services/price_tracker.dart';

// ── API & Tracker ──

final naverApiProvider = Provider<NaverShoppingApi>((ref) {
  final api = NaverShoppingApi();
  ref.onDispose(() => api.dispose());
  return api;
});

final priceTrackerProvider = FutureProvider<PriceTracker>((ref) async {
  final api = ref.read(naverApiProvider);
  final tracker = PriceTracker(api);
  await tracker.init();
  // 인기 검색어 기반으로 가격 수집 (백그라운드)
  _collectFromPopularKeywords(api, tracker);
  return tracker;
});

/// 인기 검색어로 가격 수집 (비동기, 앱 시작 시 1회)
Future<void> _collectFromPopularKeywords(
    NaverShoppingApi api, PriceTracker tracker) async {
  try {
    // 디지털/가전, 패션의류, 생활/건강 상위 키워드로 수집
    final categories = ['50000003', '50000000', '50000008'];
    final keywords = <String>[];

    for (final cid in categories) {
      try {
        final popular = await api.fetchPopularKeywords(categoryId: cid);
        keywords.addAll(popular.take(5).map((p) => p.keyword));
      } catch (_) {}
    }

    if (keywords.isNotEmpty) {
      await tracker.collectPrices(keywords);
    }
  } catch (_) {}
}

// ── 실시간 인기 검색어 (네이버 쇼핑인사이트 실제 데이터) ──

/// 전체 카테고리 인기 검색어
final popularKeywordsProvider =
    FutureProvider<List<PopularKeyword>>((ref) async {
  try {
    final api = ref.read(naverApiProvider);
    return await api.fetchAllPopularKeywords();
  } catch (_) {
    return [];
  }
});

/// 특정 카테고리 인기 검색어
final categoryPopularProvider = FutureProvider.family<List<PopularKeyword>,
    String>((ref, categoryId) async {
  try {
    final api = ref.read(naverApiProvider);
    return await api.fetchPopularKeywords(categoryId: categoryId);
  } catch (_) {
    return [];
  }
});

// ── 검색 트렌드 차트 (DataLab 기반) ──

/// 인기 검색어 상위 10개의 주간 추이 차트
final trendChartProvider =
    FutureProvider<Map<String, List<TrendChartPoint>>>((ref) async {
  try {
    final api = ref.read(naverApiProvider);

    // 디지털/가전 인기 검색어 상위 10개를 차트에 사용
    List<String> topKeywords;
    try {
      final popular = await api.fetchPopularKeywords(
        categoryId: '50000003',
        categoryName: '디지털/가전',
      );
      topKeywords = popular.take(10).map((p) => p.keyword).toList();
    } catch (_) {
      topKeywords = ['냉장고', '노트북', '에어프라이어', '가습기', '블루투스스피커'];
    }

    if (topKeywords.isEmpty) return {};

    final now = DateTime.now();
    final startDate =
        now.subtract(const Duration(days: 28)).toIso8601String().split('T')[0];
    final endDate = now.toIso8601String().split('T')[0];

    final chartData = <String, List<TrendChartPoint>>{};

    // 5개씩 배치 (병렬)
    final futures = <Future<Map<String, List<TrendChartPoint>>>>[];
    for (int i = 0; i < topKeywords.length; i += 5) {
      final batch = topKeywords.skip(i).take(5).toList();
      final groups =
          batch.map((k) => {'groupName': k, 'keywords': [k]}).toList();
      futures.add(api
          .fetchTrendChart(
            keywordGroups: groups,
            startDate: startDate,
            endDate: endDate,
          )
          .catchError((_) => <String, List<TrendChartPoint>>{}));
    }

    final results = await Future.wait(futures);
    for (final r in results) {
      chartData.addAll(r);
    }

    return chartData;
  } catch (_) {
    return {};
  }
});

// ── 네이버 쇼핑 실제 핫딜 (오늘끝딜 + 타임딜 + BEST100 병합) ──

/// 오늘끝딜 + BEST100(클릭순) + BEST100(구매순) 병렬 호출하여 병합
Future<List<Product>> _fetchAllDeals(NaverShoppingApi api) async {
  final results = await Future.wait([
    api.fetchTodayDeals().catchError((e) { debugPrint('[HotDeal] todayDeals err: $e'); return <Product>[]; }),
    api.fetchBest100(sortType: 'PRODUCT_CLICK').catchError((e) { debugPrint('[HotDeal] clickBest err: $e'); return <Product>[]; }),
    api.fetchBest100(sortType: 'PRODUCT_BUY').catchError((e) { debugPrint('[HotDeal] buyBest err: $e'); return <Product>[]; }),
  ]);

  debugPrint('[HotDeal] 오늘끝딜=${results[0].length}, 클릭BEST=${results[1].length}, 구매BEST=${results[2].length}');

  final all = <Product>[];
  for (final list in results) {
    all.addAll(list);
  }

  // id 기준 중복 제거
  final seen = <String>{};
  final unique = all.where((p) {
    if (seen.contains(p.id)) return false;
    seen.add(p.id);
    return true;
  }).toList();

  // 할인율 높은 순 정렬 후 랜덤 섞기
  // 상위 할인 상품은 앞에 유지하되 같은 구간 내에서 셔플
  unique.sort((a, b) => b.dropRate.compareTo(a.dropRate));
  final rng = Random();
  // 10개씩 구간별로 셔플 → 순서에 변화를 주되 할인율 큰 게 대체로 앞에
  for (int i = 0; i < unique.length; i += 10) {
    final end = (i + 10).clamp(0, unique.length);
    final chunk = unique.sublist(i, end)..shuffle(rng);
    unique.setRange(i, end, chunk);
  }
  return unique;
}

final hotProductsProvider = FutureProvider<List<Product>>((ref) async {
  try {
    final api = ref.read(naverApiProvider);
    final deals = await _fetchAllDeals(api);
    // 오늘끝딜은 할인율 있는 것만, BEST100은 인기상품이므로 전부 표시
    final filtered = deals.where((p) => p.dropRate > 0 || p.id.startsWith('best_')).toList();
    final bestCount = filtered.where((p) => p.id.startsWith('best_')).length;
    debugPrint('[HotDeal] 필터 후: total=${filtered.length}, best=$bestCount');
    // 오늘끝딜 카테고리 분류를 백그라운드로 미리 시작
    _classifyTodayDeals(api);
    return filtered;
  } catch (e) {
    debugPrint('[HotDeal] ERROR: $e');
    return [];
  }
});

// ── 가격 하락 상품 (축적 데이터 기반) ──

final droppedProductsProvider = FutureProvider<List<Product>>((ref) async {
  try {
    final tracker = await ref.watch(priceTrackerProvider.future);
    final dropped = tracker.getDroppedProducts(days: 7);

    return dropped.map((tp) => Product(
      id: tp.id,
      title: tp.title,
      link: tp.link,
      imageUrl: tp.imageUrl,
      currentPrice: tp.currentPrice,
      previousPrice: tp.previousPrice,
      mallName: tp.mallName,
      category1: tp.category1,
    )).toList();
  } catch (_) {
    return [];
  }
});

// ── 검색 결과 ──

final searchResultsProvider =
    FutureProvider.family<List<Product>, String>((ref, query) async {
  if (query.isEmpty) return [];
  try {
    final api = ref.read(naverApiProvider);
    final queryLower = query.toLowerCase();

    // 핫딜 상품 중 키워드 매칭 (이미 로드된 경우)
    List<Product> hotMatches = [];
    try {
      final hotState = ref.read(hotProductsProvider);
      hotState.whenData((products) {
        hotMatches = products
            .where((p) => p.title.toLowerCase().contains(queryLower))
            .toList();
      });
    } catch (_) {}

    // 일반 검색 결과
    final searchResults = await api.searchClean(query: query, display: 40);

    // 핫딜 매칭 상품을 상단에, 나머지 검색결과를 아래에 (중복 제거)
    if (hotMatches.isEmpty) return searchResults;

    final hotIds = hotMatches.map((p) => p.id).toSet();
    final filtered = searchResults.where((p) => !hotIds.contains(p.id)).toList();
    return [...hotMatches, ...filtered];
  } catch (_) {
    return [];
  }
});

// ── 카테고리 (Best100 카테고리별 직접 + 오늘끝딜 분류) ──

/// 앱 카테고리 → 네이버 쇼핑 카테고리 ID
const _appCategoryIds = <String, String>{
  '디지털/가전': '50000003',
  '패션/의류': '50000000',
  '생활/건강': '50000008',
  '식품': '50000006',
  '뷰티': '50000002',
  '스포츠/레저': '50000007',
  '출산/육아': '50000005',
};

/// 네이버 category1/2/3 → 앱 카테고리 매핑
String? _mapToAppCategory(String cat1, [String? cat2, String? cat3]) {
  final sub = '${cat2 ?? ''} ${cat3 ?? ''}'.trim();
  if (sub.contains('반려') || sub.contains('애완') || sub.contains('펫')) {
    return '반려동물';
  }
  if (cat1.contains('디지털') || cat1.contains('가전') || cat1.contains('컴퓨터') ||
      cat1.contains('휴대폰') || cat1.contains('게임')) return '디지털/가전';
  if (cat1.contains('패션') || cat1.contains('의류') || cat1.contains('잡화')) return '패션/의류';
  if (cat1.contains('화장품') || cat1.contains('미용') || cat1.contains('뷰티')) return '뷰티';
  if (cat1.contains('식품') || cat1.contains('음료')) return '식품';
  if (cat1.contains('스포츠') || cat1.contains('레저')) return '스포츠/레저';
  if (cat1.contains('출산') || cat1.contains('육아') || cat1.contains('유아')) return '출산/육아';
  if (cat1.contains('생활') || cat1.contains('건강') || cat1.contains('가구') ||
      cat1.contains('인테리어') || cat1.contains('주방') || cat1.contains('문구')) return '생활/건강';
  return null;
}

/// 상품 제목 기반 로컬 키워드 매칭으로 카테고리 분류 (API 호출 0회)
const _categoryKeywords = <String, List<String>>{
  '디지털/가전': [
    'TV', '텔레비전', '노트북', '냉장고', '세탁기', '에어컨', '건조기', '청소기',
    '이어폰', '헤드폰', '스피커', '태블릿', '모니터', '키보드', '마우스', 'SSD',
    '카메라', '게임', '컴퓨터', '프린터', '공유기', '라우터', '선풍기', '가습기',
    '제습기', '전자레인지', '오븐', '식기세척기', '밥솥', '에어프라이어', '믹서기',
    '블렌더', '다리미', '스마트폰', '휴대폰', '핸드폰', '갤럭시', '아이폰',
    '아이패드', '맥북', '그래픽카드', 'GPU', 'CPU', '메모리', 'RAM', '하드디스크',
    'HDD', 'USB', '충전기', '보조배터리', '스마트워치', '로봇청소기',
    '전기면도기', '면도기', '드라이기', '고데기', '전동칫솔', '안마기', '안마의자',
    '빔프로젝터', '프로젝터', '닌텐도', '플스', 'PS5', '엑스박스',
  ],
  '패션/의류': [
    '원피스', '자켓', '코트', '바지', '셔츠', '블라우스', '니트', '가디건',
    '운동화', '가방', '지갑', '벨트', '스니커즈', '구두', '샌들', '슬리퍼',
    '부츠', '모자', '캡', '스카프', '머플러', '장갑', '양말', '넥타이',
    '정장', '수트', '청바지', '데님', '패딩', '점퍼', '후드', '맨투맨',
    '티셔츠', '반팔', '긴팔', '레깅스', '치마', '스커트', '백팩', '크로스백',
    '토트백', '숄더백', '클러치', '선글라스', '시계', '팔찌', '목걸이', '귀걸이',
    '반지', '액세서리', '주얼리',
  ],
  '뷰티': [
    '화장품', '스킨', '로션', '세럼', '파운데이션', '립스틱', '마스카라',
    '선크림', '클렌징', '토너', '에센스', '크림', '아이섀도', '블러셔', '치크',
    '컨실러', '프라이머', '쿠션', '팩트', '립글로스', '립밤', '네일',
    '매니큐어', '향수', '퍼퓸', '바디로션', '바디워시', '샴푸', '컨디셔너',
    '린스', '트리트먼트', '헤어오일', '헤어에센스', '마스크팩', '시트마스크',
    '필링', '스크럽', '미스트', '데오드란트', '제모', '왁싱',
  ],
  '식품': [
    '과일', '고기', '수산', '김치', '라면', '커피', '음료', '견과', '반찬',
    '간식', '과자', '초콜릿', '캔디', '젤리', '빵', '케이크', '떡', '만두',
    '국수', '파스타', '소스', '양념', '식용유', '올리브유', '참기름', '소금',
    '설탕', '밀가루', '쌀', '잡곡', '계란', '달걀', '우유', '두유', '요거트',
    '치즈', '버터', '햄', '소시지', '참치', '연어', '새우', '오징어',
    '냉동식품', '즉석식품', '도시락', '선물세트', '홍삼', '꿀', '차', '주스',
    '탄산수', '생수', '맥주', '와인', '위스키', '소주',
  ],
  '생활/건강': [
    '세제', '휴지', '물티슈', '칫솔', '치약', '비타민', '유산균', '침대',
    '매트리스', '베개', '이불', '커튼', '러그', '카펫', '수건', '타올',
    '주방세제', '섬유유연제', '방향제', '탈취제', '살균', '소독', '마스크',
    '손세정제', '핸드크림', '밴드', '반창고', '체온계', '혈압계', '체중계',
    '정수기', '공기청정기', '수납', '선반', '행거', '옷걸이', '쓰레기통',
    '빗자루', '걸레', '장갑', '고무장갑', '전구', 'LED', '조명',
    '오메가3', '루테인', '프로바이오틱스', '프로틴', '단백질',
    '콜라겐', '철분', '칼슘', '마그네슘', '아연', '홍삼',
  ],
  '스포츠/레저': [
    '골프', '등산', '자전거', '요가', '헬스', '캠핑', '낚시', '수영',
    '테니스', '배드민턴', '축구', '농구', '야구', '런닝', '조깅', '트레킹',
    '등산화', '골프채', '골프공', '텐트', '침낭', '랜턴', '버너', '쿨러',
    '아이스박스', '낚싯대', '릴', '웨이트', '덤벨', '바벨', '매트',
    '폼롤러', '짐볼', '밴드', '수영복', '래쉬가드', '고글', '스키',
    '보드', '스노보드', '인라인', '킥보드', '스쿠터',
  ],
  '출산/육아': [
    '기저귀', '분유', '유모차', '아기', '유아', '어린이', '젖병', '이유식',
    '물티슈', '아기띠', '카시트', '보행기', '장난감', '블록', '인형',
    '동화책', '그림책', '아기옷', '바디슈트', '턱받이', '수유', '수유쿠션',
    '임산부', '산모', '출산', '태교', '아기침대', '범퍼침대', '놀이매트',
  ],
  '반려동물': [
    '강아지', '고양이', '사료', '펫', '반려견', '반려묘', '캣', '독',
    '간식', '껌', '스낵', '하네스', '목줄', '리드줄', '장난감', '캣타워',
    '배변패드', '모래', '캣모래', '샴푸', '미용', '빗', '브러시',
    '이동장', '캐리어', '하우스', '쿨매트', '방석', '침대',
  ],
};

String? _classifyByTitle(String title) {
  final lower = title.toLowerCase();
  for (final entry in _categoryKeywords.entries) {
    for (final keyword in entry.value) {
      if (lower.contains(keyword.toLowerCase())) {
        return entry.key;
      }
    }
  }
  return null;
}

/// 오늘끝딜 카테고리 분류 (캐시 + 동시 요청 방지)
final _dealCatCache = <String, String>{};
DateTime? _dealCatCacheTime;
Future<Map<String, String>>? _pendingDealCat;

/// 새로고침 시 캐시 초기화
void clearDealCategoryCache() {
  _dealCatCache.clear();
  _dealCatCacheTime = null;
  _pendingDealCat = null;
}

Future<Map<String, String>> _classifyTodayDeals(NaverShoppingApi api) async {
  if (_dealCatCacheTime != null &&
      DateTime.now().difference(_dealCatCacheTime!) < const Duration(minutes: 30) &&
      _dealCatCache.isNotEmpty) {
    return _dealCatCache;
  }
  if (_pendingDealCat != null) return _pendingDealCat!;
  _pendingDealCat = _doClassifyTodayDeals(api);
  try {
    return await _pendingDealCat!;
  } finally {
    _pendingDealCat = null;
  }
}

Future<Map<String, String>> _doClassifyTodayDeals(NaverShoppingApi api) async {
  final deals = await api.fetchTodayDeals(); // 이미 캐시됨
  final result = <String, String>{};

  // 로컬 키워드 매칭으로 분류 (API 호출 0회)
  for (final p in deals) {
    // 1차: 네이버 카테고리 정보가 있으면 활용
    final cat = _mapToAppCategory(p.category1, p.category2, p.category3);
    if (cat != null) {
      result[p.id] = cat;
      continue;
    }
    // 2차: 제목 기반 키워드 매칭
    final titleCat = _classifyByTitle(p.title);
    if (titleCat != null) {
      result[p.id] = titleCat;
    }
  }

  debugPrint('[Category] 오늘끝딜 분류: ${result.length}/${deals.length}');
  _dealCatCache..clear()..addAll(result);
  _dealCatCacheTime = DateTime.now();
  return result;
}

final categoryDealsProvider =
    FutureProvider.family<List<Product>, String>((ref, category) async {
  try {
    final api = ref.read(naverApiProvider);

    // 1. 카테고리별 Best100 (1회 호출)
    List<Product> best100;
    if (category == '반려동물') {
      best100 = await api.searchClean(query: '반려동물 인기상품', display: 100);
    } else {
      final catId = _appCategoryIds[category];
      if (catId == null) return [];
      best100 = await api.fetchBest100(categoryId: catId);
    }

    // 2. 오늘끝딜 중 해당 카테고리 상품 추가 (~14회 호출, 캐시됨)
    final todayDeals = await api.fetchTodayDeals();
    final dealCategories = await _classifyTodayDeals(api);
    final matchingDeals = todayDeals
        .where((p) => dealCategories[p.id] == category && p.dropRate > 0)
        .toList();

    // 3. 병합 (오늘끝딜 상단, 중복 제거) + 구간 셔플
    final seen = best100.map((p) => p.id).toSet();
    final merged = [
      ...matchingDeals.where((p) => !seen.contains(p.id)),
      ...best100,
    ];
    merged.sort((a, b) => b.dropRate.compareTo(a.dropRate));
    final rng = Random();
    for (int i = 0; i < merged.length; i += 10) {
      final end = (i + 10).clamp(0, merged.length);
      final chunk = merged.sublist(i, end)..shuffle(rng);
      merged.setRange(i, end, chunk);
    }
    return merged;
  } catch (_) {
    return [];
  }
});

// ── 내가 본 상품 기록 ──

final viewedProductsProvider =
    StateNotifierProvider<ViewedProductsNotifier, List<Product>>((ref) {
  return ViewedProductsNotifier();
});

class ViewedProductsNotifier extends StateNotifier<List<Product>> {
  ViewedProductsNotifier() : super([]);

  void add(Product product) {
    // 중복 제거 후 맨 앞에 추가
    state = [
      product,
      ...state.where((p) => p.id != product.id),
    ].take(50).toList();
  }
}

// ── 트렌드 키워드 (검색 화면용 - 실제 인기 검색어) ──

final trendKeywordsProvider =
    FutureProvider<List<TrendKeyword>>((ref) async {
  final api = ref.read(naverApiProvider);

  // 1차: BEST 키워드 랭킹 API (순위 변동 데이터 포함)
  try {
    final keywords = await api.fetchKeywordRank();
    if (keywords.isNotEmpty) return keywords;
  } catch (_) {}

  // 2차: DataLab Shopping Insight 인기 검색어
  final allKeywords = <TrendKeyword>[];
  try {
    final categories = ['50000003', '50000000', '50000002', '50000008'];
    for (final cid in categories) {
      try {
        final popular = await api.fetchPopularKeywords(categoryId: cid);
        for (final p in popular.take(5)) {
          allKeywords.add(TrendKeyword(
            keyword: p.keyword,
            ratio: (10 - p.rank + 1).toDouble(),
          ));
        }
      } catch (_) {}
    }
  } catch (_) {}

  if (allKeywords.isNotEmpty) {
    final seen = <String>{};
    return allKeywords.where((t) {
      if (seen.contains(t.keyword)) return false;
      seen.add(t.keyword);
      return true;
    }).toList();
  }

  // 3차: 핫딜 상품명에서 키워드 추출
  try {
    final deals = await api.fetchTodayDeals();
    for (final d in deals.where((p) => p.dropRate > 0).take(20)) {
      var name = d.title.replaceAll(RegExp(r'\[.*?\]'), '').trim();
      final words = name.split(' ').where((w) => w.length > 1).toList();
      if (words.isNotEmpty) {
        final keyword = words.take(2).join(' ');
        allKeywords.add(TrendKeyword(keyword: keyword, ratio: d.dropRate));
      }
    }
  } catch (_) {}

  final seen = <String>{};
  return allKeywords.where((t) {
    if (seen.contains(t.keyword)) return false;
    seen.add(t.keyword);
    return true;
  }).toList();
});

