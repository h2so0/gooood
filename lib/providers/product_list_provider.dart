import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/product.dart';

// ── 공용 유틸 ──

final _rng = Random();

/// 판매처 ID prefix로 소스 감지
String _sourceOf(Product p) {
  final id = p.id;
  if (id.startsWith('deal_')) return 'naver_deal';
  if (id.startsWith('best_')) return 'naver_best';
  if (id.startsWith('live_')) return 'naver_live';
  if (id.startsWith('promo_')) return 'naver_promo';
  if (id.startsWith('11st_')) return '11st';
  if (id.startsWith('gmkt_')) return 'gmarket';
  if (id.startsWith('auction_')) return 'auction';
  return 'other';
}

/// 판매처 균등 배분 + 전체 랜덤 셔플
List<Product> balancedShuffle(List<Product> products) {
  // 1) 소스별 그룹핑
  final groups = <String, List<Product>>{};
  for (final p in products) {
    groups.putIfAbsent(_sourceOf(p), () => []).add(p);
  }

  // 2) 각 소스 내부 셔플
  for (final list in groups.values) {
    list.shuffle(_rng);
  }

  // 3) 라운드로빈으로 판매처 균등 배분
  final result = <Product>[];
  final sources = groups.values.where((l) => l.isNotEmpty).toList();
  sources.shuffle(_rng); // 소스 순서도 랜덤

  final maxLen = sources.fold<int>(0, (m, l) => l.length > m ? l.length : m);
  for (int i = 0; i < maxLen; i++) {
    for (final list in sources) {
      if (i < list.length) {
        result.add(list[i]);
      }
    }
  }

  return result;
}

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

// ── HotProductsNotifier ──

class HotProductsNotifier extends StateNotifier<ProductListState> {
  static const _displaySize = 20;

  /// 전체 상품 풀 (셔플 대상)
  List<Product> _pool = [];
  int _cursor = 0;

  HotProductsNotifier() : super(const ProductListState()) {
    _loadPool();
  }

  Future<void> _loadPool() async {
    state = state.copyWith(isLoading: true);

    try {
      // 전체 상품 한 번에 가져오기 (dropRate > 0만)
      final snapshot = await FirebaseFirestore.instance
          .collection('products')
          .where('dropRate', isGreaterThan: 0)
          .orderBy('dropRate', descending: true)
          .limit(300)
          .get();

      final all = snapshot.docs.map((doc) {
        return Product.fromJson(doc.data());
      }).toList();

      // 판매처별 균등 배분 후 전체 셔플
      _pool = balancedShuffle(all);
      _cursor = 0;

      // 첫 페이지 표시
      _showNextPage();
    } catch (e) {
      debugPrint('[HotProducts] loadPool error: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  void _showNextPage() {
    final end = (_cursor + _displaySize).clamp(0, _pool.length);
    final page = _pool.sublist(_cursor, end);
    _cursor = end;

    state = ProductListState(
      products: [...state.products, ...page],
      isLoading: false,
      hasMore: _cursor < _pool.length,
    );
  }

  Future<void> fetchNextPage() async {
    if (state.isLoading || !state.hasMore) return;
    _showNextPage();
  }

  Future<void> refresh() async {
    state = const ProductListState();
    _pool.clear();
    _cursor = 0;
    await _loadPool();
  }
}

// ── CategoryProductsNotifier ──

class CategoryProductsNotifier extends StateNotifier<ProductListState> {
  static const _displaySize = 20;
  final CategoryFilter filter;

  /// 카테고리별 전체 풀 캐시 (중카테고리 전환 시 Firestore 재쿼리 방지)
  static final _fullCategoryPool = <String, List<Product>>{};

  List<Product> _pool = [];
  int _cursor = 0;

  CategoryProductsNotifier(this.filter) : super(const ProductListState()) {
    _loadPool();
  }

  Future<void> _loadPool() async {
    state = state.copyWith(isLoading: true);

    try {
      List<Product> all;

      if (filter.subCategory != null) {
        // 중카테고리 선택 시: 캐시에서 필터링 (Firestore 쿼리 0회)
        final cached = _fullCategoryPool[filter.category];
        if (cached != null) {
          all = cached
              .where((p) => p.subCategory == filter.subCategory)
              .toList();
        } else {
          // 캐시 미스: Firestore에서 직접 쿼리
          final snapshot = await FirebaseFirestore.instance
              .collection('products')
              .where('category', isEqualTo: filter.category)
              .where('subCategory', isEqualTo: filter.subCategory)
              .orderBy('dropRate', descending: true)
              .limit(200)
              .get();

          all = snapshot.docs.map((doc) {
            return Product.fromJson(doc.data());
          }).toList();
        }
      } else {
        // "전체" 탭: Firestore 쿼리 후 캐시에 저장
        final snapshot = await FirebaseFirestore.instance
            .collection('products')
            .where('category', isEqualTo: filter.category)
            .orderBy('dropRate', descending: true)
            .limit(200)
            .get();

        all = snapshot.docs.map((doc) {
          return Product.fromJson(doc.data());
        }).toList();

        _fullCategoryPool[filter.category] = all;
      }

      _pool = balancedShuffle(all);
      _cursor = 0;
      _showNextPage();
    } catch (e) {
      debugPrint('[CategoryProducts] loadPool error: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  void _showNextPage() {
    final end = (_cursor + _displaySize).clamp(0, _pool.length);
    final page = _pool.sublist(_cursor, end);
    _cursor = end;

    state = ProductListState(
      products: [...state.products, ...page],
      isLoading: false,
      hasMore: _cursor < _pool.length,
    );
  }

  Future<void> fetchNextPage() async {
    if (state.isLoading || !state.hasMore) return;
    _showNextPage();
  }

  Future<void> refresh() async {
    _fullCategoryPool.remove(filter.category);
    state = const ProductListState();
    _pool.clear();
    _cursor = 0;
    await _loadPool();
  }
}

// ── Providers ──

final hotProductsProvider =
    StateNotifierProvider<HotProductsNotifier, ProductListState>(
  (ref) => HotProductsNotifier(),
);

final categoryProductsProvider =
    StateNotifierProvider.autoDispose.family<CategoryProductsNotifier,
        ProductListState, CategoryFilter>(
  (ref, filter) => CategoryProductsNotifier(filter),
);
