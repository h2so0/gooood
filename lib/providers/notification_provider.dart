import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';
import '../services/device_profile_sync.dart';

class NotificationSettings {
  final bool hotDeal;
  final bool saleSoonEnd;
  final bool dailyBest;
  final Set<String> categories;
  final int quietStartHour;
  final int quietEndHour;
  final bool priceDrop;
  final bool categoryAlert;
  final bool smartDigest;

  const NotificationSettings({
    this.hotDeal = true,
    this.saleSoonEnd = true,
    this.dailyBest = false,
    this.categories = const {},
    this.quietStartHour = 22,
    this.quietEndHour = 8,
    this.priceDrop = true,
    this.categoryAlert = true,
    this.smartDigest = false,
  });

  NotificationSettings copyWith({
    bool? hotDeal,
    bool? saleSoonEnd,
    bool? dailyBest,
    Set<String>? categories,
    int? quietStartHour,
    int? quietEndHour,
    bool? priceDrop,
    bool? categoryAlert,
    bool? smartDigest,
  }) {
    return NotificationSettings(
      hotDeal: hotDeal ?? this.hotDeal,
      saleSoonEnd: saleSoonEnd ?? this.saleSoonEnd,
      dailyBest: dailyBest ?? this.dailyBest,
      categories: categories ?? this.categories,
      quietStartHour: quietStartHour ?? this.quietStartHour,
      quietEndHour: quietEndHour ?? this.quietEndHour,
      priceDrop: priceDrop ?? this.priceDrop,
      categoryAlert: categoryAlert ?? this.categoryAlert,
      smartDigest: smartDigest ?? this.smartDigest,
    );
  }
}

class NotificationSettingsNotifier extends StateNotifier<NotificationSettings> {
  NotificationSettingsNotifier() : super(const NotificationSettings()) {
    _load();
  }

  final _service = NotificationService();

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = NotificationSettings(
      hotDeal: prefs.getBool('noti_hotDeal') ?? true,
      saleSoonEnd: prefs.getBool('noti_saleSoonEnd') ?? true,
      dailyBest: prefs.getBool('noti_dailyBest') ?? false,
      categories: (prefs.getStringList('noti_categories') ?? []).toSet(),
      quietStartHour: prefs.getInt('noti_quietStart') ?? 22,
      quietEndHour: prefs.getInt('noti_quietEnd') ?? 8,
      priceDrop: prefs.getBool('noti_priceDrop') ?? true,
      categoryAlert: prefs.getBool('noti_categoryAlert') ?? true,
      smartDigest: prefs.getBool('noti_smartDigest') ?? false,
    );
    // 로드 후 토픽 동기화
    _syncTopics();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('noti_hotDeal', state.hotDeal);
    await prefs.setBool('noti_saleSoonEnd', state.saleSoonEnd);
    await prefs.setBool('noti_dailyBest', state.dailyBest);
    await prefs.setStringList('noti_categories', state.categories.toList());
    await prefs.setInt('noti_quietStart', state.quietStartHour);
    await prefs.setInt('noti_quietEnd', state.quietEndHour);
    await prefs.setBool('noti_priceDrop', state.priceDrop);
    await prefs.setBool('noti_categoryAlert', state.categoryAlert);
    await prefs.setBool('noti_smartDigest', state.smartDigest);
  }

  void _toggle(
    NotificationSettings Function(NotificationSettings) updater, {
    bool syncTopics = false,
  }) {
    state = updater(state);
    _save();
    syncTopics ? _syncTopics() : DeviceProfileSync().syncNow();
  }

  void toggleHotDeal() => _toggle((s) => s.copyWith(hotDeal: !s.hotDeal), syncTopics: true);
  void toggleSaleSoonEnd() => _toggle((s) => s.copyWith(saleSoonEnd: !s.saleSoonEnd), syncTopics: true);
  void toggleDailyBest() => _toggle((s) => s.copyWith(dailyBest: !s.dailyBest), syncTopics: true);
  void togglePriceDrop() => _toggle((s) => s.copyWith(priceDrop: !s.priceDrop));
  void toggleCategoryAlert() => _toggle((s) => s.copyWith(categoryAlert: !s.categoryAlert));
  void toggleSmartDigest() => _toggle((s) => s.copyWith(smartDigest: !s.smartDigest));

  void toggleCategory(String category) {
    final cats = Set<String>.from(state.categories);
    if (cats.contains(category)) {
      cats.remove(category);
    } else {
      cats.add(category);
    }
    state = state.copyWith(categories: cats);
    _save();
    _syncTopics();
  }

  /// 최초 알림 허용 시 전체 알림 ON
  Future<void> enableAllOnFirstPermission() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('noti_initialized') == true) return;

    state = state.copyWith(
      hotDeal: true,
      saleSoonEnd: true,
      dailyBest: true,
      priceDrop: true,
      categoryAlert: true,
      smartDigest: true,
    );
    await prefs.setBool('noti_initialized', true);
    _save();
    _syncTopics();
    DeviceProfileSync().syncNow();
  }

  void setQuietHours(int start, int end) {
    state = state.copyWith(quietStartHour: start, quietEndHour: end);
    _save();
    DeviceProfileSync().syncNow();
  }

  /// FCM 토픽 구독 상태를 설정값과 동기화
  void _syncTopics() {
    if (kIsWeb) return;

    // 핫딜 토픽
    if (state.hotDeal) {
      _service.subscribeToTopic(FcmTopics.hotDeal);
    } else {
      _service.unsubscribeFromTopic(FcmTopics.hotDeal);
    }

    // 마감임박 토픽
    if (state.saleSoonEnd) {
      _service.subscribeToTopic(FcmTopics.saleEnd);
    } else {
      _service.unsubscribeFromTopic(FcmTopics.saleEnd);
    }

    // 일일베스트 토픽
    if (state.dailyBest) {
      _service.subscribeToTopic(FcmTopics.dailyBest);
    } else {
      _service.unsubscribeFromTopic(FcmTopics.dailyBest);
    }

    // 카테고리별 핫딜 토픽
    for (final entry in FcmTopics.categoryIds.entries) {
      final topic = FcmTopics.hotDealCategory(entry.value);
      if (state.hotDeal && state.categories.contains(entry.key)) {
        _service.subscribeToTopic(topic);
      } else {
        _service.unsubscribeFromTopic(topic);
      }
    }
  }
}

final notificationSettingsProvider =
    StateNotifierProvider<NotificationSettingsNotifier, NotificationSettings>(
        (ref) => NotificationSettingsNotifier());
