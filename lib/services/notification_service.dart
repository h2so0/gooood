import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

// ──────────────────────────────────────────
// 백그라운드 FCM 메시지 핸들러 (top-level)
// ──────────────────────────────────────────

const _historyBoxName = 'notification_history';
const _maxHistoryCount = 100;

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Hive.initFlutter();
    if (!Hive.isBoxOpen(_historyBoxName)) {
      await Hive.openBox<String>(_historyBoxName);
    }
    await _saveHistoryFromMessage(message);
  } catch (_) {}
}

Future<void> _saveHistoryFromMessage(RemoteMessage message) async {
  final box = Hive.box<String>(_historyBoxName);
  final notification = message.notification;
  final data = message.data;

  final record = {
    'title': notification?.title ?? data['title'] ?? '',
    'body': notification?.body ?? data['body'] ?? '',
    'type': data['type'] ?? 'general',
    'productId': data['productId'],
    'timestamp': DateTime.now().toIso8601String(),
    'isRead': false,
  };
  await box.add(jsonEncode(record));

  // 크기 제한
  if (box.length > _maxHistoryCount) {
    final keysToRemove =
        box.keys.take(box.length - _maxHistoryCount).toList();
    await box.deleteAll(keysToRemove);
  }
}

// ──────────────────────────────────────────
// FCM 토픽 이름 상수
// ──────────────────────────────────────────

class FcmTopics {
  static const hotDeal = 'hotDeal';
  static const saleEnd = 'saleEnd';
  static const dailyBest = 'dailyBest';

  /// 카테고리별 핫딜 토픽
  static String hotDealCategory(String categoryId) =>
      'hotDeal_$categoryId';

  static const categoryIds = {
    '디지털/가전': '50000003',
    '패션의류': '50000000',
    '화장품/미용': '50000002',
    '생활/건강': '50000008',
    '식품': '50000006',
    '스포츠/레저': '50000007',
    '출산/육아': '50000005',
    '패션잡화': '50000001',
    '가구/인테리어': '50000004',
  };
}

// ──────────────────────────────────────────
// NotificationService (싱글톤)
// ──────────────────────────────────────────

class NotificationService {
  NotificationService._();
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localPlugin =
      FlutterLocalNotificationsPlugin();

  /// 전체 초기화
  Future<void> initialize() async {
    if (kIsWeb) return;

    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Seoul'));

    // 로컬 알림 플러그인 초기화 (포그라운드 표시용)
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _localPlugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );

    // Android 알림 채널 생성
    final androidPlugin = _localPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'hot_deal',
          '핫딜 알림',
          description: '30% 이상 할인 상품 알림',
          importance: Importance.high,
        ),
      );
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'sale_end',
          '마감 임박 알림',
          description: '종료 1시간 이내 상품 알림',
          importance: Importance.high,
        ),
      );
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'daily_best',
          '오늘의 BEST',
          description: '매일 아침 인기 상품 알림',
          importance: Importance.defaultImportance,
        ),
      );
    }

    // 알림 내역 박스 열기
    if (!Hive.isBoxOpen(_historyBoxName)) {
      await Hive.openBox<String>(_historyBoxName);
    }

    // FCM 백그라운드 핸들러 등록
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // FCM 포그라운드 메시지 리스너
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
  }

  /// 권한 요청 (Android 13+ / iOS)
  Future<void> requestPermission() async {
    if (kIsWeb) return;

    // FCM 권한 요청
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Android 13+ 로컬 알림 권한
    final androidPlugin = _localPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
  }

  /// 초기 토픽 구독 (SharedPreferences 기반 설정에 따라)
  Future<void> subscribeInitialTopics() async {
    if (kIsWeb) return;

    // iOS 시뮬레이터는 APNS를 지원하지 않으므로 토큰 확인 후 구독
    final apnsToken = await _messaging.getAPNSToken();
    if (defaultTargetPlatform == TargetPlatform.iOS && apnsToken == null) {
      return;
    }

    // 기본값: hotDeal ON, saleEnd ON, dailyBest OFF
    // notification_provider가 로드된 후 _syncTopics에서 정확히 동기화됨
    // 여기서는 최소한의 기본 구독만
    await _messaging.subscribeToTopic(FcmTopics.hotDeal);
    await _messaging.subscribeToTopic(FcmTopics.saleEnd);
  }

  // ── 토픽 구독/해제 ──

  Future<void> subscribeToTopic(String topic) async {
    if (kIsWeb) return;
    await _messaging.subscribeToTopic(topic);
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    if (kIsWeb) return;
    await _messaging.unsubscribeFromTopic(topic);
  }

  // ── 포그라운드 메시지 처리 ──

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    final data = message.data;
    if (notification == null && data.isEmpty) return;

    final title = notification?.title ?? data['title'] ?? '';
    final body = notification?.body ?? data['body'] ?? '';
    final type = data['type'] ?? 'general';

    // 로컬 알림으로 표시
    String channelId;
    switch (type) {
      case 'hotDeal':
        channelId = 'hot_deal';
        break;
      case 'saleEnd':
        channelId = 'sale_end';
        break;
      case 'dailyBest':
        channelId = 'daily_best';
        break;
      default:
        channelId = 'hot_deal';
    }

    await _localPlugin.show(
      message.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelId,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );

    // 내역 저장
    await _saveHistoryFromMessage(message);
  }

  // ── 알림 내역 조회/관리 ──

  List<Map<String, dynamic>> getHistory() {
    if (kIsWeb) return [];
    final box = Hive.box<String>(_historyBoxName);
    final records = <Map<String, dynamic>>[];
    for (int i = box.length - 1; i >= 0; i--) {
      final raw = box.getAt(i);
      if (raw != null) {
        records.add(jsonDecode(raw) as Map<String, dynamic>);
      }
    }
    return records;
  }

  int getUnreadCount() {
    if (kIsWeb) return 0;
    if (!Hive.isBoxOpen(_historyBoxName)) return 0;
    final box = Hive.box<String>(_historyBoxName);
    int count = 0;
    for (int i = 0; i < box.length; i++) {
      final raw = box.getAt(i);
      if (raw != null) {
        final record = jsonDecode(raw) as Map<String, dynamic>;
        if (record['isRead'] != true) count++;
      }
    }
    return count;
  }

  Future<void> markAllAsRead() async {
    if (kIsWeb) return;
    final box = Hive.box<String>(_historyBoxName);
    for (int i = 0; i < box.length; i++) {
      final raw = box.getAt(i);
      if (raw != null) {
        final record = jsonDecode(raw) as Map<String, dynamic>;
        if (record['isRead'] != true) {
          record['isRead'] = true;
          await box.putAt(i, jsonEncode(record));
        }
      }
    }
  }

  Future<void> clearHistory() async {
    if (kIsWeb) return;
    final box = Hive.box<String>(_historyBoxName);
    await box.clear();
  }
}
