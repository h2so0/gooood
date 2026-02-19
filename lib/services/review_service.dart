import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 앱 내 리뷰 요청 — 조건을 충족하면 시스템 리뷰 다이얼로그 표시.
///
/// 트리거 조건 (모두 만족해야 함):
///   1. 앱 첫 실행 후 3일 이상 경과
///   2. 상품 상세 조회 누적 5회 이상
///   3. 마지막 리뷰 요청 후 90일 이상 경과 (또는 한 번도 요청한 적 없음)
class ReviewService {
  static const _keyInstallDate = 'review_install_date';
  static const _keyViewCount = 'review_view_count';
  static const _keyLastPrompt = 'review_last_prompt';

  static const _minDaysSinceInstall = 3;
  static const _minViewCount = 5;
  static const _cooldownDays = 90;

  /// 상품 상세 진입 시 호출 — 조회 수를 증가시키고 조건 체크.
  static Future<void> recordProductView() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 첫 실행 날짜 기록
      if (!prefs.containsKey(_keyInstallDate)) {
        prefs.setString(_keyInstallDate, DateTime.now().toIso8601String());
      }

      // 조회 카운트 증가
      final count = (prefs.getInt(_keyViewCount) ?? 0) + 1;
      prefs.setInt(_keyViewCount, count);

      // 조건 충족 여부 확인
      if (!_meetsConditions(prefs, count)) return;

      // 시스템 리뷰 다이얼로그 요청
      final reviewer = InAppReview.instance;
      if (await reviewer.isAvailable()) {
        await reviewer.requestReview();
        prefs.setString(_keyLastPrompt, DateTime.now().toIso8601String());
        debugPrint('[Review] 리뷰 요청 표시');
      }
    } catch (e) {
      debugPrint('[Review] error: $e');
    }
  }

  static bool _meetsConditions(SharedPreferences prefs, int viewCount) {
    // 조건 1: 조회 수
    if (viewCount < _minViewCount) return false;

    // 조건 2: 설치 후 경과일
    final installStr = prefs.getString(_keyInstallDate);
    if (installStr == null) return false;
    final installDate = DateTime.tryParse(installStr);
    if (installDate == null) return false;
    if (DateTime.now().difference(installDate).inDays < _minDaysSinceInstall) {
      return false;
    }

    // 조건 3: 쿨다운
    final lastStr = prefs.getString(_keyLastPrompt);
    if (lastStr != null) {
      final lastPrompt = DateTime.tryParse(lastStr);
      if (lastPrompt != null &&
          DateTime.now().difference(lastPrompt).inDays < _cooldownDays) {
        return false;
      }
    }

    return true;
  }
}
