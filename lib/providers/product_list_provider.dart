import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../constants/app_constants.dart';
import '../models/product.dart';
import '../models/sort_option.dart';

// ── 타입 ──

class CategoryFilter {
  final String category;
  final String? subCategory;

  const CategoryFilter({required this.category, this.subCategory});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CategoryFilter &&
          category == other.category &&
          subCategory == other.subCategory;

  @override
  int get hashCode => Object.hash(category, subCategory);
}

class ProductListState {
  final List<Product> products;
  final bool isLoading;
  final bool hasMore;
  final DocumentSnapshot? lastDocument;

  const ProductListState({
    this.products = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.lastDocument,
  });

  ProductListState copyWith({
    List<Product>? products,
    bool? isLoading,
    bool? hasMore,
    DocumentSnapshot? lastDocument,
    bool clearLastDocument = false,
  }) {
    return ProductListState(
      products: products ?? this.products,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      lastDocument:
          clearLastDocument ? null : (lastDocument ?? this.lastDocument),
    );
  }
}

// ── 공통 페이지네이션 베이스 ──

abstract class PaginatedProductsNotifier
    extends StateNotifier<ProductListState> {
  static const pageSize = PaginationConfig.pageSize;

  int startOffset = 0;
  bool wrapped = false;
  int _refreshGen = 0;

  PaginatedProductsNotifier() : super(const ProductListState()) {
    fetchPage();
  }

  @protected
  String get logTag;

  @protected
  Future<Query> buildQuery();

  @protected
  Future<int> countTotal();

  @protected
  Future<void> onEmptyFirstPage() async {}

  @protected
  Future<void> fetchPage() async {
    state = state.copyWith(isLoading: true);

    try {
      Query query = await buildQuery();

      if (state.lastDocument != null) {
        query = query.startAfterDocument(state.lastDocument!);
      }

      final snapshot = await query.get();
      final now = DateTime.now();
      final page = snapshot.docs
          .map((doc) => Product.fromJson(doc.data() as Map<String, dynamic>))
          .where((p) {
            if (p.saleEndDate == null) return true;
            try { return DateTime.parse(p.saleEndDate!).isAfter(now); }
            catch (_) { return true; }
          })
          .toList();

      if (page.isEmpty && state.products.isEmpty) {
        await onEmptyFirstPage();
        if (state.isLoading) {
          state = state.copyWith(isLoading: false);
        }
        return;
      }

      // 기존 ID 셋으로 중복 제거
      final existingIds = state.products.map((p) => p.id).toSet();
      final deduped = page.where((p) => !existingIds.contains(p.id)).toList();

      // Wrap around: 끝에 도달 → 0부터 재시작
      if (page.length < pageSize && !wrapped && startOffset > 0) {
        wrapped = true;
        state = ProductListState(
          products: [...state.products, ...deduped],
          isLoading: false,
          hasMore: true,
          lastDocument: null,
        );
        return;
      }

      state = ProductListState(
        products: [...state.products, ...deduped],
        isLoading: false,
        hasMore: snapshot.docs.length >= pageSize,
        lastDocument: snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
      );
    } catch (e) {
      debugPrint('[$logTag] fetchPage error: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> fetchNextPage() async {
    if (state.isLoading || !state.hasMore) return;
    await fetchPage();
  }

  Future<void> refresh() async {
    final gen = ++_refreshGen;
    wrapped = false;
    state = state.copyWith(isLoading: true);

    final total = await countTotal();
    if (gen != _refreshGen) return; // 새 refresh가 시작됨

    startOffset = total > pageSize ? Random().nextInt(total) : 0;

    state = const ProductListState();
    await fetchPage();
  }
}

// ── HotProductsNotifier ──

class HotProductsNotifier extends PaginatedProductsNotifier {
  bool _useFeedOrder = true;
  bool _isFirstFetch = true;
  static const _cacheKey = 'hot_first_page';

  /// 첫 페이지 결과를 Hive에 저장
  void _saveCacheIfFirstPage() {
    if (state.products.isEmpty) return;
    try {
      final box = Hive.box(HiveBoxes.feedCache);
      final items = state.products.take(PaginatedProductsNotifier.pageSize * 2).toList();
      box.put(_cacheKey, jsonEncode(items.map((p) => p.toJson()).toList()));
    } catch (e) {
      debugPrint('[HotProducts] cache save error: $e');
    }
  }

  @override
  String get logTag => 'HotProducts';

  @override
  Future<Query> buildQuery() async {
    final col = FirebaseFirestore.instance.collection('products');

    if (_useFeedOrder) {
      if (wrapped) {
        return col
            .where('feedOrder', isGreaterThanOrEqualTo: 0)
            .where('feedOrder', isLessThan: startOffset)
            .orderBy('feedOrder')
            .limit(PaginatedProductsNotifier.pageSize);
      }
      return col
          .where('feedOrder', isGreaterThanOrEqualTo: startOffset)
          .orderBy('feedOrder')
          .limit(PaginatedProductsNotifier.pageSize);
    }

    return col
        .where('dropRate', isGreaterThan: 0)
        .orderBy('dropRate', descending: true)
        .limit(PaginatedProductsNotifier.pageSize);
  }

  @override
  Future<void> fetchPage() async {
    if (_isFirstFetch) {
      // 첫 번째 Firestore 응답: SWR 캐시를 교체 (dedup 방지)
      _isFirstFetch = false;
      state = state.copyWith(isLoading: true);

      try {
        Query query = await buildQuery();
        final snapshot = await query.get();
        final now = DateTime.now();
        final page = snapshot.docs
            .map((doc) => Product.fromJson(doc.data() as Map<String, dynamic>))
            .where((p) {
              if (p.saleEndDate == null) return true;
              try { return DateTime.parse(p.saleEndDate!).isAfter(now); }
              catch (_) { return true; }
            })
            .toList();

        if (page.isEmpty) {
          await onEmptyFirstPage();
          return;
        }

        state = ProductListState(
          products: page,
          isLoading: false,
          hasMore: snapshot.docs.length >= PaginatedProductsNotifier.pageSize,
          lastDocument: snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
        );
        _saveCacheIfFirstPage();
      } catch (e) {
        debugPrint('[$logTag] first fetchPage error: $e');
        state = state.copyWith(isLoading: false);
      }
      return;
    }

    await super.fetchPage();
  }

  @override
  Future<int> countTotal() async {
    final countSnap = await FirebaseFirestore.instance
        .collection('products')
        .where('feedOrder', isGreaterThanOrEqualTo: 0)
        .count()
        .get();
    return countSnap.count ?? 0;
  }

  @override
  Future<void> onEmptyFirstPage() async {
    if (!_useFeedOrder) return;
    // feedOrder 범위 끝에 걸려 빈 페이지 → 0부터 재시도
    if (startOffset > 0) {
      startOffset = 0;
      await fetchPage();
      return;
    }
    // startOffset=0인데도 비었으면 fallback
    _useFeedOrder = false;
    await fetchPage();
  }

  @override
  Future<void> refresh() async {
    _useFeedOrder = true;
    _isFirstFetch = true;
    await super.refresh();
    _saveCacheIfFirstPage();
  }
}

// ── CategoryProductsNotifier ──

class CategoryProductsNotifier extends PaginatedProductsNotifier {
  final CategoryFilter filter;
  bool _useFallback = false;

  CategoryProductsNotifier(this.filter);

  @override
  String get logTag => 'CategoryProducts';

  @override
  Future<Query> buildQuery() async {
    if (_useFallback) return _buildFallbackQuery();

    final col = FirebaseFirestore.instance.collection('products');
    Query base;

    if (filter.subCategory != null) {
      base = col
          .where('category', isEqualTo: filter.category)
          .where('subCategory', isEqualTo: filter.subCategory);
    } else {
      base = col.where('category', isEqualTo: filter.category);
    }

    if (wrapped && startOffset > 0) {
      return base
          .where('categoryFeedOrder', isGreaterThanOrEqualTo: 0)
          .where('categoryFeedOrder', isLessThan: startOffset)
          .orderBy('categoryFeedOrder')
          .limit(PaginatedProductsNotifier.pageSize);
    }

    if (startOffset > 0) {
      return base
          .where('categoryFeedOrder', isGreaterThanOrEqualTo: startOffset)
          .orderBy('categoryFeedOrder')
          .limit(PaginatedProductsNotifier.pageSize);
    }

    return base
        .orderBy('categoryFeedOrder')
        .limit(PaginatedProductsNotifier.pageSize);
  }

  Query _buildFallbackQuery() {
    final col = FirebaseFirestore.instance.collection('products');
    Query query;

    if (filter.subCategory != null) {
      query = col
          .where('category', isEqualTo: filter.category)
          .where('subCategory', isEqualTo: filter.subCategory)
          .orderBy('dropRate', descending: true)
          .limit(PaginatedProductsNotifier.pageSize);
    } else {
      query = col
          .where('category', isEqualTo: filter.category)
          .orderBy('dropRate', descending: true)
          .limit(PaginatedProductsNotifier.pageSize);
    }

    return query;
  }

  @override
  Future<int> countTotal() async {
    final countQuery = filter.subCategory != null
        ? FirebaseFirestore.instance
            .collection('products')
            .where('category', isEqualTo: filter.category)
            .where('subCategory', isEqualTo: filter.subCategory)
            .count()
        : FirebaseFirestore.instance
            .collection('products')
            .where('category', isEqualTo: filter.category)
            .count();
    final countSnap = await countQuery.get();
    return countSnap.count ?? 0;
  }

  @override
  Future<void> fetchPage() async {
    try {
      await super.fetchPage();
    } catch (e) {
      if (e.toString().contains('failed-precondition') ||
          e.toString().contains('requires an index')) {
        _useFallback = true;
        state = state.copyWith(isLoading: false);
        await super.fetchPage();
        return;
      }
      rethrow;
    }
  }

  @override
  Future<void> refresh() async {
    _useFallback = false;
    await super.refresh();
  }
}

// ── SourceFilteredProductsNotifier ──

class SourceFilteredProductsNotifier extends PaginatedProductsNotifier {
  final List<String> sources;
  bool _useFallback = false;

  SourceFilteredProductsNotifier(this.sources);

  @override
  String get logTag => 'SourceFiltered(${sources.join(",")})';

  @override
  Future<Query> buildQuery() async {
    final col = FirebaseFirestore.instance.collection('products');
    if (_useFallback) {
      return col
          .where('source', whereIn: sources)
          .limit(PaginatedProductsNotifier.pageSize);
    }

    // feedOrder 기반 랜덤 오프셋 페이지네이션 (새로고침 시 순서 변경)
    if (wrapped) {
      return col
          .where('source', whereIn: sources)
          .where('feedOrder', isGreaterThanOrEqualTo: 0)
          .where('feedOrder', isLessThan: startOffset)
          .orderBy('feedOrder')
          .limit(PaginatedProductsNotifier.pageSize);
    }
    if (startOffset > 0) {
      return col
          .where('source', whereIn: sources)
          .where('feedOrder', isGreaterThanOrEqualTo: startOffset)
          .orderBy('feedOrder')
          .limit(PaginatedProductsNotifier.pageSize);
    }
    return col
        .where('source', whereIn: sources)
        .orderBy('feedOrder')
        .limit(PaginatedProductsNotifier.pageSize);
  }

  @override
  Future<void> fetchPage() async {
    try {
      await super.fetchPage();
    } catch (e) {
      if (!_useFallback &&
          (e.toString().contains('failed-precondition') ||
              e.toString().contains('requires an index'))) {
        debugPrint('[$logTag] index missing, using fallback');
        _useFallback = true;
        state = state.copyWith(isLoading: false);
        await super.fetchPage();
        return;
      }
      rethrow;
    }
  }

  @override
  Future<int> countTotal() async {
    final countSnap = await FirebaseFirestore.instance
        .collection('products')
        .where('source', whereIn: sources)
        .count()
        .get();
    return countSnap.count ?? 0;
  }

  @override
  Future<void> onEmptyFirstPage() async {
    if (startOffset > 0) {
      startOffset = 0;
      await fetchPage();
      return;
    }
    // feedOrder가 없으면 fallback
    if (!_useFallback) {
      _useFallback = true;
      await fetchPage();
    }
  }

  @override
  Future<void> refresh() async {
    _useFallback = false;
    await super.refresh();
  }
}

// ── Source filter tab definitions ──

class SourceTab {
  final String label;
  /// Comma-joined source keys (used as Riverpod family key).
  /// null = 전체 (uses hotProductsProvider instead).
  final String? sourceKey;
  final List<String>? sources;
  /// 판매처 시그니처 색상. null = 전체 탭
  final int? colorValue;
  /// 탭에 표시할 심볼 텍스트 (예: "N", "11", "G")
  final String? symbol;
  const SourceTab(this.label, this.sourceKey, this.sources, {this.colorValue, this.symbol});
}

const sourceFilterTabs = <SourceTab>[
  SourceTab('전체', null, null),
  SourceTab('네이버', 'best100,todayDeal,shoppingLive,naverPromo',
      ['best100', 'todayDeal', 'shoppingLive', 'naverPromo'],
      colorValue: 0xFF03C75A, symbol: 'N'),
  SourceTab('11번가', '11st', ['11st'],
      colorValue: 0xFFFF0033, symbol: '11'),
  SourceTab('G마켓', 'gmarket', ['gmarket'],
      colorValue: 0xFF00A650, symbol: 'G'),
  SourceTab('옥션', 'auction', ['auction'],
      colorValue: 0xFFE60033, symbol: 'A'),
  SourceTab('롯데ON', 'lotteon', ['lotteon'],
      colorValue: 0xFFE50011, symbol: 'L'),
  SourceTab('SSG', 'ssg', ['ssg'],
      colorValue: 0xFFF2A900, symbol: 'S'),
];

// ── TimeDealProductsNotifier ──

class TimeDealProductsNotifier extends PaginatedProductsNotifier {
  @override
  String get logTag => 'TimeDeal';

  @override
  Future<Query> buildQuery() async {
    final now = DateTime.now().toIso8601String();
    return FirebaseFirestore.instance
        .collection('products')
        .where('saleEndDate', isGreaterThan: now)
        .orderBy('saleEndDate')
        .limit(PaginatedProductsNotifier.pageSize);
  }

  @override
  Future<int> countTotal() async {
    final now = DateTime.now().toIso8601String();
    final snap = await FirebaseFirestore.instance
        .collection('products')
        .where('saleEndDate', isGreaterThan: now)
        .count()
        .get();
    return snap.count ?? 0;
  }

  @override
  Future<void> refresh() async {
    wrapped = false;
    startOffset = 0;
    state = const ProductListState();
    await fetchPage();
  }
}

// ── DropRateSortedNotifier (홈 피드 할인율순) ──

class DropRateSortedNotifier extends PaginatedProductsNotifier {
  @override
  String get logTag => 'DropRateSorted';

  @override
  Future<Query> buildQuery() async {
    return FirebaseFirestore.instance
        .collection('products')
        .where('dropRate', isGreaterThan: 0)
        .orderBy('dropRate', descending: true)
        .limit(PaginatedProductsNotifier.pageSize);
  }

  @override
  Future<int> countTotal() async {
    final snap = await FirebaseFirestore.instance
        .collection('products')
        .where('dropRate', isGreaterThan: 0)
        .count()
        .get();
    return snap.count ?? 0;
  }

  @override
  Future<void> refresh() async {
    wrapped = false;
    startOffset = 0;
    state = const ProductListState();
    await fetchPage();
  }
}

// ── CategoryDropRateNotifier (카테고리 할인율순) ──

class CategoryDropRateNotifier extends PaginatedProductsNotifier {
  final String category;

  CategoryDropRateNotifier(this.category);

  @override
  String get logTag => 'CategoryDropRate($category)';

  @override
  Future<Query> buildQuery() async {
    return FirebaseFirestore.instance
        .collection('products')
        .where('category', isEqualTo: category)
        .orderBy('dropRate', descending: true)
        .limit(PaginatedProductsNotifier.pageSize);
  }

  @override
  Future<int> countTotal() async {
    final snap = await FirebaseFirestore.instance
        .collection('products')
        .where('category', isEqualTo: category)
        .count()
        .get();
    return snap.count ?? 0;
  }

  @override
  Future<void> refresh() async {
    wrapped = false;
    startOffset = 0;
    state = const ProductListState();
    await fetchPage();
  }
}

// ── 클라이언트 사이드 정렬 헬퍼 ──

List<Product> applySortOption(List<Product> products, SortOption sort) {
  switch (sort) {
    case SortOption.dropRate:
      return [...products]..sort((a, b) => b.dropRate.compareTo(a.dropRate));
    case SortOption.priceLow:
      return [...products]..sort((a, b) => a.currentPrice.compareTo(b.currentPrice));
    case SortOption.priceHigh:
      return [...products]..sort((a, b) => b.currentPrice.compareTo(a.currentPrice));
    case SortOption.review:
      return [...products]..sort((a, b) {
        final scoreA = a.reviewScore ?? 0;
        final scoreB = b.reviewScore ?? 0;
        final cmp = scoreB.compareTo(scoreA);
        if (cmp != 0) return cmp;
        return (b.reviewCount ?? 0).compareTo(a.reviewCount ?? 0);
      });
    default:
      return products;
  }
}

// ── Providers ──

final hotProductsProvider =
    StateNotifierProvider<HotProductsNotifier, ProductListState>(
  (ref) => HotProductsNotifier(),
);

final timeDealProductsProvider =
    StateNotifierProvider<TimeDealProductsNotifier, ProductListState>(
  (ref) => TimeDealProductsNotifier(),
);

final dropRateSortedProvider =
    StateNotifierProvider<DropRateSortedNotifier, ProductListState>(
  (ref) => DropRateSortedNotifier(),
);

final categoryDropRateProvider = StateNotifierProvider.autoDispose
    .family<CategoryDropRateNotifier, ProductListState, String>(
  (ref, category) => CategoryDropRateNotifier(category),
);

final sourceFilteredProductsProvider = StateNotifierProvider.autoDispose
    .family<SourceFilteredProductsNotifier, ProductListState, String>(
  (ref, key) {
    final sources = key.split(',');
    return SourceFilteredProductsNotifier(sources);
  },
);

final categoryProductsProvider =
    StateNotifierProvider.autoDispose.family<CategoryProductsNotifier,
        ProductListState, CategoryFilter>(
  (ref, filter) => CategoryProductsNotifier(filter),
);

// ── Sort state providers ──

final homeSortProvider = StateProvider<SortOption>((ref) => SortOption.recommended);

final categorySortProvider = StateProvider.family<SortOption, String>(
  (ref, category) => SortOption.recommended,
);

final timeDealSortProvider = StateProvider<SortOption>((ref) => SortOption.recommended);
