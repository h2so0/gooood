import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/naver_shopping_api.dart';

final naverApiProvider = Provider<NaverShoppingApi>((ref) {
  final api = NaverShoppingApi();
  ref.onDispose(() => api.dispose());
  return api;
});
