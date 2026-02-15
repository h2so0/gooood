import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/product.dart';

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

class HotProductsNotifier extends StateNotifier<ProductListState> {
  static const _displaySize = 20;

  /// 전체 상품 풀 (셔플 대상)
  List<Product> _pool = [];
  int _cursor = 0;
  final _rng = Random();

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
      _pool = _balancedShuffle(all);
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
  List<Product> _balancedShuffle(List<Product> products) {
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
}

class CategoryProductsNotifier extends StateNotifier<ProductListState> {
  static const _displaySize = 20;
  final CategoryFilter filter;

  List<Product> _pool = [];
  int _cursor = 0;
  final _rng = Random();

  CategoryProductsNotifier(this.filter) : super(const ProductListState()) {
    _loadPool();
  }

  Future<void> _loadPool() async {
    state = state.copyWith(isLoading: true);

    try {
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance
          .collection('products')
          .where('category', isEqualTo: filter.category);

      if (filter.subCategory != null) {
        query = query.where('subCategory', isEqualTo: filter.subCategory);
      }

      final snapshot = await query
          .orderBy('dropRate', descending: true)
          .limit(200)
          .get();

      final all = snapshot.docs.map((doc) {
        return Product.fromJson(doc.data());
      }).toList();

      _pool = _balancedShuffle(all);
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
    state = const ProductListState();
    _pool.clear();
    _cursor = 0;
    await _loadPool();
  }

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

  List<Product> _balancedShuffle(List<Product> products) {
    final groups = <String, List<Product>>{};
    for (final p in products) {
      groups.putIfAbsent(_sourceOf(p), () => []).add(p);
    }

    for (final list in groups.values) {
      list.shuffle(_rng);
    }

    final result = <Product>[];
    final sources = groups.values.where((l) => l.isNotEmpty).toList();
    sources.shuffle(_rng);

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
}

final hotProductsProvider =
    StateNotifierProvider<HotProductsNotifier, ProductListState>(
  (ref) => HotProductsNotifier(),
);

final categoryProductsProvider = StateNotifierProvider.family<
    CategoryProductsNotifier, ProductListState, CategoryFilter>(
  (ref, filter) => CategoryProductsNotifier(filter),
);
