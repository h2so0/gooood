import 'package:hive_flutter/hive_flutter.dart';
export 'package:hive_flutter/hive_flutter.dart' show Box;

/// Hive 박스 열기 헬퍼 — isBoxOpen 가드 패턴 통합
Future<Box<T>> getOrOpenBox<T>(String name) async {
  if (Hive.isBoxOpen(name)) return Hive.box<T>(name);
  return Hive.openBox<T>(name);
}
