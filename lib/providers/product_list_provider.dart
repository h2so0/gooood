import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/product.dart';

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

// ── HotProductsNotifier (서버 페이지네이션) ──

class HotProductsNotifier extends StateNotifier<ProductListState> {
  static const _pageSize = 20;

  /// feedOrder 사용 가능 여부 (첫 페이지에서 1회 판별)
  bool? _useFeedOrder;

  HotProductsNotifier() : super(const ProductListState()) {
    _fetchPage();
  }

  Future<void> _fetchPage() async {
    state = state.copyWith(isLoading: true);

    try {
      // 첫 페이지에서만 feedOrder 존재 여부 확인
      if (_useFeedOrder == null) {
        final testSnap = await FirebaseFirestore.instance
            .collection('products')
            .where('feedOrder', isGreaterThanOrEqualTo: 0)
            .limit(1)
            .get();
        _useFeedOrder = testSnap.docs.isNotEmpty;
      }

      Query query;

      if (_useFeedOrder!) {
        query = FirebaseFirestore.instance
            .collection('products')
            .where('feedOrder', isGreaterThanOrEqualTo: 0)
            .orderBy('feedOrder')
            .limit(_pageSize);
      } else {
        query = FirebaseFirestore.instance
            .collection('products')
            .where('dropRate', isGreaterThan: 0)
            .orderBy('dropRate', descending: true)
            .limit(_pageSize);
      }

      if (state.lastDocument != null) {
        query = query.startAfterDocument(state.lastDocument!);
      }

      final snapshot = await query.get();
      final page = snapshot.docs.map((doc) {
        return Product.fromJson(doc.data() as Map<String, dynamic>);
      }).toList();

      state = ProductListState(
        products: [...state.products, ...page],
        isLoading: false,
        hasMore: page.length >= _pageSize,
        lastDocument: snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
      );
    } catch (e) {
      debugPrint('[HotProducts] fetchPage error: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> fetchNextPage() async {
    if (state.isLoading || !state.hasMore) return;
    await _fetchPage();
  }

  Future<void> refresh() async {
    _useFeedOrder = null;
    state = const ProductListState();
    await _fetchPage();
  }
}

// ── CategoryProductsNotifier (서버 페이지네이션) ──

class CategoryProductsNotifier extends StateNotifier<ProductListState> {
  static const _pageSize = 20;
  final CategoryFilter filter;

  CategoryProductsNotifier(this.filter) : super(const ProductListState()) {
    _fetchPage();
  }

  Future<void> _fetchPage() async {
    state = state.copyWith(isLoading: true);

    try {
      Query query;

      if (filter.subCategory != null) {
        query = FirebaseFirestore.instance
            .collection('products')
            .where('category', isEqualTo: filter.category)
            .where('subCategory', isEqualTo: filter.subCategory)
            .orderBy('categoryFeedOrder')
            .limit(_pageSize);
      } else {
        query = FirebaseFirestore.instance
            .collection('products')
            .where('category', isEqualTo: filter.category)
            .orderBy('categoryFeedOrder')
            .limit(_pageSize);
      }

      if (state.lastDocument != null) {
        query = query.startAfterDocument(state.lastDocument!);
      }

      final snapshot = await query.get();
      final page = snapshot.docs.map((doc) {
        return Product.fromJson(doc.data() as Map<String, dynamic>);
      }).toList();

      state = ProductListState(
        products: [...state.products, ...page],
        isLoading: false,
        hasMore: page.length >= _pageSize,
        lastDocument: snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
      );
    } catch (e) {
      debugPrint('[CategoryProducts] fetchPage error: $e');

      // categoryFeedOrder 인덱스 미생성 시 dropRate 폴백
      if (e.toString().contains('failed-precondition') ||
          e.toString().contains('requires an index')) {
        await _fetchPageFallback();
        return;
      }

      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> _fetchPageFallback() async {
    try {
      Query query;

      if (filter.subCategory != null) {
        query = FirebaseFirestore.instance
            .collection('products')
            .where('category', isEqualTo: filter.category)
            .where('subCategory', isEqualTo: filter.subCategory)
            .orderBy('dropRate', descending: true)
            .limit(_pageSize);
      } else {
        query = FirebaseFirestore.instance
            .collection('products')
            .where('category', isEqualTo: filter.category)
            .orderBy('dropRate', descending: true)
            .limit(_pageSize);
      }

      if (state.lastDocument != null) {
        query = query.startAfterDocument(state.lastDocument!);
      }

      final snapshot = await query.get();
      final page = snapshot.docs.map((doc) {
        return Product.fromJson(doc.data() as Map<String, dynamic>);
      }).toList();

      state = ProductListState(
        products: [...state.products, ...page],
        isLoading: false,
        hasMore: page.length >= _pageSize,
        lastDocument: snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
      );
    } catch (e) {
      debugPrint('[CategoryProducts] fallback error: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> fetchNextPage() async {
    if (state.isLoading || !state.hasMore) return;
    await _fetchPage();
  }

  Future<void> refresh() async {
    state = const ProductListState();
    await _fetchPage();
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
