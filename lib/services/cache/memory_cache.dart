import '../../constants/app_constants.dart';

class CacheEntry<T> {
  final T data;
  final DateTime createdAt;
  CacheEntry(this.data) : createdAt = DateTime.now();
  bool get isExpired =>
      DateTime.now().difference(createdAt) > CacheDurations.standard;
}

class MemoryCache {
  final Map<String, CacheEntry<dynamic>> _store = {};

  T? get<T>(String key) {
    final entry = _store[key];
    if (entry != null && !entry.isExpired) return entry.data as T;
    return null;
  }

  void put<T>(String key, T data) {
    _store[key] = CacheEntry<T>(data);
  }

  void clear() => _store.clear();
}
