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

// ── 카테고리 (핫딜 상품을 카테고리별로 필터링) ──

const _categoryKeywords = <String, List<String>>{
  '디지털/가전': [
    '노트북', '갤럭시', '아이폰', '아이패드', '에어팟', '버즈', '워치',
    '냉장고', '세탁기', '청소기', '에어컨', '건조기', '전자레인지',
    '스마트TV', '텔레비전', 'OLED', 'QLED', '인치TV',
    '모니터', '스피커', '이어폰', '헤드폰', '충전기', '배터리',
    '태블릿', '키보드', '마우스', '공기청정기', '가습기', '제습기',
    '건전지', '카메라', '프린터', 'SSD', 'USB', '드라이기',
    '로봇청소기', '식기세척기', '전기포트', '믹서기',
  ],
  '패션/의류': [
    '티셔츠', '반팔', '긴팔', '바지', '팬츠', '자켓', '코트', '패딩',
    '원피스', '스커트', '후드', '집업', '맨투맨', '니트', '셔츠',
    '운동화', '스니커즈', '슬리퍼', '구두', '부츠', '양말',
    '스파오', '무신사', '아디다스', '나이키', '뉴발란스', '베이직하우스',
    '잡화', '가방', '지갑', '벨트', '모자', '청바지', '레깅스',
    '블라우스', '카디건', '트렌치', '점퍼', '조끼',
  ],
  '생활/건강': [
    '비타민', '영양제', '유산균', '프로바이오틱스', '오메가', '루테인',
    '밀크씨슬', '엽산', '철분', '칼슘', '마그네슘', '콜라겐', '알부민',
    '세제', '섬유유연제', '핸드워시', '치약', '칫솔', '세정제',
    '장갑', '도마', '지퍼백', '행주', '수세미', '청소용품', '걸레',
    '베개', '이불', '침구', '토퍼', '매트리스',
    '온열', '찜질', '안대', '체중계', '혈압계',
    '주방용품', '채칼', '냄비', '프라이팬', '텀블러', '물통',
    '규조토', '수건', '발매트', '펜트리', '수납', '정리함',
    '방석', '등받이쿠션',
  ],
  '식품': [
    '소스', '파스타', '떡볶이', '라면', '국밥', '순대', '김치',
    '쿠키', '과자', '약과', '인절미', '케이크', '초콜릿',
    '커피', '홍차', '두유', '우유', '음료', '주스',
    '참치', '런천미트', '소시지', '육포', '불고기',
    '사과', '망고', '딸기', '레드향', '바나나',
    '견과', '아몬드', '호두', '캐슈넛', '선물세트',
    '양념', '간장', '된장', '고추장', '식용유', '올리브오일',
    '쌀', '현미', '잡곡', '꼬막', '비빔밥',
    '그래놀라', '시리얼', '에너지바', '프로틴바',
    '냉동식품', '밀키트', '즉석밥', '통조림',
  ],
  '뷰티': [
    'EDT', '향수', '퍼퓸', '오드', '설화수', '에스티로더',
    '샴푸', '린스', '컨디셔너', '트리트먼트', '헤어에센스',
    '로션', '세럼', '에센스', '토너', '스킨케어',
    '선크림', '자외선', 'SPF', '쿠션팩트', '파운데이션', '립스틱',
    '마스카라', '아이라이너', '클렌징', '클렌징폼', '클렌징오일',
    '바디로션', '핸드크림', '바세린',
    '탈모샴푸', '두피케어', '염색약',
    '화장품', '메이크업', '뷰티', '스킨로션', '팩트',
    '틴트', '아이섀도', '컨실러', '프라이머', '미스트',
  ],
  '스포츠/레저': [
    '헬스', '요가매트', '필라테스', '등산', '캠핑',
    '자전거', '러닝화', '수영', '수영복', '골프', '테니스',
    '가민', '스마트밴드', '만보기',
    '텐트', '침낭', '랜턴', '여행가방', '캠핑용품',
    '에너지젤', '프로틴쉐이크', '헬스장갑', '아령', '덤벨',
    '요가복', '등산화', '골프채', '배드민턴', '축구공',
  ],
  '출산/육아': [
    '기저귀', '분유', '이유식', '젖병', '아기옷', '유아용',
    '키즈', '주니어', '레고', '장난감', '동화책',
    '유모차', '카시트', '어린이집', '돌잔치',
    '유아식', '아기침대', '보행기',
  ],
  '반려동물': [
    '강아지', '고양이', '사료', '펫푸드', '펫용품',
    '반려견', '반려묘', '애견', '애묘', '캣타워', '목줄', '배변패드',
    '강아지간식', '고양이간식', '펫샴푸', '스크래처',
  ],
};

/// 카테고리 분류: 키워드 매칭 점수 기반 (가장 많이 매칭되는 카테고리 선택)
String _classifyCategory(String title) {
  final lower = title.toLowerCase();
  String bestCategory = '기타';
  int bestScore = 0;

  for (final entry in _categoryKeywords.entries) {
    int score = 0;
    for (final kw in entry.value) {
      if (lower.contains(kw.toLowerCase())) score++;
    }
    if (score > bestScore) {
      bestScore = score;
      bestCategory = entry.key;
    }
  }
  return bestCategory;
}

final categoryDealsProvider =
    FutureProvider.family<List<Product>, String>((ref, category) async {
  try {
    final api = ref.read(naverApiProvider);
    final deals = await _fetchAllDeals(api);
    // 해당 카테고리에 맞는 핫딜만 필터링
    final filtered = deals
        .where((p) => p.dropRate > 0 && _classifyCategory(p.title) == category)
        .toList();
    if (filtered.isNotEmpty) return filtered;
    // 분류 안 된 상품이 많으면 할인율 있는 것만이라도
    return deals.where((p) => p.dropRate > 0).toList();
  } catch (_) {
    return [];
  }
});

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

