import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';

class NotificationSettings {
  final bool hotDeal;
  final bool saleSoonEnd;
  final bool dailyBest;
  final Set<String> categories;
  final int quietStartHour;
  final int quietEndHour;

  const NotificationSettings({
    this.hotDeal = true,
    this.saleSoonEnd = true,
    this.dailyBest = false,
    this.categories = const {},
    this.quietStartHour = 22,
    this.quietEndHour = 8,
  });

  NotificationSettings copyWith({
    bool? hotDeal,
    bool? saleSoonEnd,
    bool? dailyBest,
    Set<String>? categories,
    int? quietStartHour,
    int? quietEndHour,
  }) {
    return NotificationSettings(
      hotDeal: hotDeal ?? this.hotDeal,
      saleSoonEnd: saleSoonEnd ?? this.saleSoonEnd,
      dailyBest: dailyBest ?? this.dailyBest,
      categories: categories ?? this.categories,
      quietStartHour: quietStartHour ?? this.quietStartHour,
      quietEndHour: quietEndHour ?? this.quietEndHour,
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
  }

  void toggleHotDeal() {
    state = state.copyWith(hotDeal: !state.hotDeal);
    _save();
    _syncTopics();
  }

  void toggleSaleSoonEnd() {
    state = state.copyWith(saleSoonEnd: !state.saleSoonEnd);
    _save();
    _syncTopics();
  }

  void toggleDailyBest() {
    state = state.copyWith(dailyBest: !state.dailyBest);
    _save();
    _syncTopics();
  }

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

  void setQuietHours(int start, int end) {
    state = state.copyWith(quietStartHour: start, quietEndHour: end);
    _save();
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
