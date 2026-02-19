import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_constants.dart';
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

// ── 공통 페이지네이션 베이스 ──

abstract class PaginatedProductsNotifier
    extends StateNotifier<ProductListState> {
  static const pageSize = PaginationConfig.pageSize;

  int startOffset = 0;
  bool wrapped = false;

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

      // Wrap around: 끝에 도달 → 0부터 재시작
      if (page.length < pageSize && !wrapped && startOffset > 0) {
        wrapped = true;
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
        hasMore: page.length >= pageSize,
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
    wrapped = false;

    final total = await countTotal();
    startOffset = total > pageSize ? Random().nextInt(total) : 0;

    state = const ProductListState();
    await fetchPage();
  }
}

// ── HotProductsNotifier ──

class HotProductsNotifier extends PaginatedProductsNotifier {
  bool _useFeedOrder = true;

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
    if (_useFeedOrder) {
      _useFeedOrder = false;
      await fetchPage();
    }
  }

  @override
  Future<void> refresh() async {
    _useFeedOrder = true;
    await super.refresh();
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
