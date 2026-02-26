import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../constants/app_constants.dart';

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
  } catch (e) { debugPrint('[NotificationService] background handler error: $e'); }
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

  static const categoryIds = shoppingCategoryIds;
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

  /// 알림 탭 콜백 (main.dart에서 설정)
  void Function(Map<String, dynamic> data)? _onNotificationTap;

  void setOnNotificationTap(void Function(Map<String, dynamic> data) callback) {
    _onNotificationTap = callback;
  }

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
      onDidReceiveNotificationResponse: _onLocalNotificationTap,
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
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'personalized',
          '맞춤 알림',
          description: '가격 하락, 관심 카테고리, 맞춤 추천 알림',
          importance: Importance.high,
        ),
      );
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'keyword_price_alert',
          '키워드 목표가 알림',
          description: '찜한 키워드가 목표가에 도달했을 때 알림',
          importance: Importance.high,
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
      case 'keywordAlert':
        channelId = 'keyword_price_alert';
        break;
      case 'priceDrop':
      case 'categoryInterest':
      case 'smartDigest':
        channelId = 'personalized';
        break;
      default:
        channelId = 'hot_deal';
    }

    // payload에 productId 전달 (탭 시 랜딩용)
    final payload = data['productId'] as String? ?? '';

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
      payload: payload,
    );

    // 내역 저장
    await _saveHistoryFromMessage(message);
  }

  // ── 키워드 가격 알림 ──

  Future<void> showKeywordPriceAlert({
    required String keyword,
    required int currentMin,
    required int targetPrice,
  }) async {
    final title = '목표가 도달!';
    final body = '"$keyword" 최저가 ${_formatPrice(currentMin)}원 (목표: ${_formatPrice(targetPrice)}원)';

    await _localPlugin.show(
      'keyword_$keyword'.hashCode,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'keyword_price_alert',
          '키워드 목표가 알림',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: 'keyword:$keyword',
    );

    // 내역 저장
    final box = Hive.box<String>(_historyBoxName);
    final record = {
      'title': title,
      'body': body,
      'type': 'keywordAlert',
      'keyword': keyword,
      'timestamp': DateTime.now().toIso8601String(),
      'isRead': false,
    };
    await box.add(jsonEncode(record));
  }

  String _formatPrice(int price) {
    final str = price.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buffer.write(',');
      buffer.write(str[i]);
    }
    return buffer.toString();
  }

  // ── 로컬 알림 탭 처리 ──

  void _onLocalNotificationTap(NotificationResponse response) {
    final productId = response.payload;
    if (productId == null || productId.isEmpty) return;
    _onNotificationTap?.call({'productId': productId});
  }

  // ── 중복 방지 알림 저장 (탭 핸들러에서 호출) ──

  /// 백그라운드/종료 상태에서 알림 탭 시 히스토리에 저장.
  /// 최근 10개 중 동일 title+type이 5분 이내에 존재하면 skip (배경 핸들러 중복 방지).
  Future<void> saveToHistoryIfNotDuplicate(RemoteMessage message) async {
    if (kIsWeb) return;

    final notification = message.notification;
    final data = message.data;
    final title = notification?.title ?? data['title'] ?? '';
    final type = data['type'] ?? 'general';
    final now = DateTime.now();

    if (!Hive.isBoxOpen(_historyBoxName)) {
      try {
        await Hive.openBox<String>(_historyBoxName);
      } catch (e) {
        debugPrint('[NotificationService] failed to open history box: $e');
        return;
      }
    }
    final box = Hive.box<String>(_historyBoxName);
    // 최근 10개 레코드에서 중복 체크
    final recentCount = box.length < 10 ? box.length : 10;
    for (int i = box.length - 1; i >= box.length - recentCount; i--) {
      final raw = box.getAt(i);
      if (raw == null) continue;
      final record = jsonDecode(raw) as Map<String, dynamic>;
      if (record['title'] == title && record['type'] == type) {
        final ts = DateTime.tryParse(record['timestamp'] ?? '');
        if (ts != null && now.difference(ts).inMinutes < 5) {
          return; // 중복 — skip
        }
      }
    }

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
        final record = jsonDecode(raw) as Map<String, dynamic>;
        record['_boxIndex'] = i; // 개별 삭제용 인덱스
        records.add(record);
      }
    }
    return records;
  }

  Future<void> deleteAt(int boxIndex) async {
    if (kIsWeb) return;
    final box = Hive.box<String>(_historyBoxName);
    if (boxIndex >= 0 && boxIndex < box.length) {
      await box.deleteAt(boxIndex);
    }
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
