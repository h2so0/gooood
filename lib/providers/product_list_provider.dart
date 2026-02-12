import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/product.dart';

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
  static const _pageSize = 20;

  HotProductsNotifier() : super(const ProductListState()) {
    fetchNextPage();
  }

  Future<void> fetchNextPage() async {
    if (state.isLoading || !state.hasMore) return;
    state = state.copyWith(isLoading: true);

    try {
      Query query = FirebaseFirestore.instance
          .collection('products')
          .where('dropRate', isGreaterThan: 0)
          .orderBy('dropRate', descending: true)
          .limit(_pageSize);

      if (state.lastDocument != null) {
        query = query.startAfterDocument(state.lastDocument!);
      }

      final snapshot = await query.get();
      final newProducts = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return Product.fromJson(data);
      }).toList();

      state = state.copyWith(
        products: [...state.products, ...newProducts],
        isLoading: false,
        hasMore: newProducts.length >= _pageSize,
        lastDocument:
            snapshot.docs.isNotEmpty ? snapshot.docs.last : state.lastDocument,
      );
    } catch (e) {
      debugPrint('[HotProducts] fetchNextPage error: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> refresh() async {
    state = const ProductListState();
    await fetchNextPage();
  }
}

class CategoryProductsNotifier extends StateNotifier<ProductListState> {
  static const _pageSize = 20;
  final String category;

  CategoryProductsNotifier(this.category) : super(const ProductListState()) {
    fetchNextPage();
  }

  Future<void> fetchNextPage() async {
    if (state.isLoading || !state.hasMore) return;
    state = state.copyWith(isLoading: true);

    try {
      Query query = FirebaseFirestore.instance
          .collection('products')
          .where('category', isEqualTo: category)
          .orderBy('dropRate', descending: true)
          .limit(_pageSize);

      if (state.lastDocument != null) {
        query = query.startAfterDocument(state.lastDocument!);
      }

      final snapshot = await query.get();
      final newProducts = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return Product.fromJson(data);
      }).toList();

      state = state.copyWith(
        products: [...state.products, ...newProducts],
        isLoading: false,
        hasMore: newProducts.length >= _pageSize,
        lastDocument:
            snapshot.docs.isNotEmpty ? snapshot.docs.last : state.lastDocument,
      );
    } catch (e) {
      debugPrint('[CategoryProducts] fetchNextPage error: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> refresh() async {
    state = const ProductListState();
    await fetchNextPage();
  }
}

final hotProductsProvider =
    StateNotifierProvider<HotProductsNotifier, ProductListState>(
  (ref) => HotProductsNotifier(),
);

final categoryProductsProvider = StateNotifierProvider.family<
    CategoryProductsNotifier, ProductListState, String>(
  (ref, category) => CategoryProductsNotifier(category),
);
