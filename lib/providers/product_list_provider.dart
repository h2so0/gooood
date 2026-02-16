import 'dart:math';
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

  bool? _useFeedOrder;
  int _startOffset = 0;
  bool _wrapped = false;

  HotProductsNotifier() : super(const ProductListState()) {
    _fetchPage();
  }

  Future<void> _fetchPage() async {
    state = state.copyWith(isLoading: true);

    try {
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
        final col = FirebaseFirestore.instance.collection('products');
        if (_wrapped) {
          // Phase 2: 0부터 시작점 직전까지만 조회 (중복 방지)
          query = col
              .where('feedOrder', isGreaterThanOrEqualTo: 0)
              .where('feedOrder', isLessThan: _startOffset)
              .orderBy('feedOrder')
              .limit(_pageSize);
        } else {
          // Phase 1: 시작점부터 끝까지
          query = col
              .where('feedOrder', isGreaterThanOrEqualTo: _startOffset)
              .orderBy('feedOrder')
              .limit(_pageSize);
        }
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

      // feedOrder 끝에 도달 → 0부터 wrap around
      if (page.length < _pageSize && _useFeedOrder! && !_wrapped && _startOffset > 0) {
        _wrapped = true;
        state = ProductListState(
          products: [...state.products, ...page],
          isLoading: false,
          hasMore: true,
          lastDocument: null,
        );
        return;
      }

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
    _wrapped = false;

    // 랜덤 시작점으로 순서 변경
    final countSnap = await FirebaseFirestore.instance
        .collection('products')
        .where('feedOrder', isGreaterThanOrEqualTo: 0)
        .count()
        .get();
    final total = countSnap.count ?? 0;
    _startOffset = total > _pageSize ? Random().nextInt(total) : 0;

    state = const ProductListState();
    await _fetchPage();
  }
}

// ── CategoryProductsNotifier (서버 페이지네이션) ──

class CategoryProductsNotifier extends StateNotifier<ProductListState> {
  static const _pageSize = 20;
  final CategoryFilter filter;

  int _startOffset = 0;
  bool _wrapped = false;
  bool _useFallback = false;

  CategoryProductsNotifier(this.filter) : super(const ProductListState()) {
    _fetchPage();
  }

  Query _buildQuery({bool wrapped = false}) {
    final col = FirebaseFirestore.instance.collection('products');
    Query base;

    if (filter.subCategory != null) {
      base = col
          .where('category', isEqualTo: filter.category)
          .where('subCategory', isEqualTo: filter.subCategory);
    } else {
      base = col.where('category', isEqualTo: filter.category);
    }

    if (wrapped && _startOffset > 0) {
      // Phase 2: 0부터 시작점 직전까지만 (중복 방지)
      return base
          .where('categoryFeedOrder', isGreaterThanOrEqualTo: 0)
          .where('categoryFeedOrder', isLessThan: _startOffset)
          .orderBy('categoryFeedOrder')
          .limit(_pageSize);
    }

    return base.orderBy('categoryFeedOrder').limit(_pageSize);
  }

  Future<void> _fetchPage() async {
    if (_useFallback) {
      await _fetchPageFallback();
      return;
    }

    state = state.copyWith(isLoading: true);

    try {
      Query query = _buildQuery(wrapped: _wrapped);

      // 첫 페이지에서 startOffset 적용
      if (state.lastDocument == null && _startOffset > 0 && !_wrapped) {
        query = query.startAt([_startOffset]);
      } else if (state.lastDocument != null) {
        query = query.startAfterDocument(state.lastDocument!);
      }

      final snapshot = await query.get();
      final page = snapshot.docs.map((doc) {
        return Product.fromJson(doc.data() as Map<String, dynamic>);
      }).toList();

      // 끝 도달 → 0부터 wrap around
      if (page.length < _pageSize && !_wrapped && _startOffset > 0) {
        _wrapped = true;
        state = ProductListState(
          products: [...state.products, ...page],
          isLoading: false,
          hasMore: true,
          lastDocument: null,
        );
        return;
      }

      state = ProductListState(
        products: [...state.products, ...page],
        isLoading: false,
        hasMore: page.length >= _pageSize,
        lastDocument: snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
      );
    } catch (e) {
      debugPrint('[CategoryProducts] fetchPage error: $e');

      if (e.toString().contains('failed-precondition') ||
          e.toString().contains('requires an index')) {
        _useFallback = true;
        await _fetchPageFallback();
        return;
      }

      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> _fetchPageFallback() async {
    state = state.copyWith(isLoading: true);

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
    _wrapped = false;
    _useFallback = false;

    // 랜덤 시작점으로 순서 변경
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
    final total = countSnap.count ?? 0;
    _startOffset = total > _pageSize ? Random().nextInt(total) : 0;

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
