import 'package:app_links/app_links.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'firebase_options.dart';
import 'models/product.dart';
import 'providers/notification_provider.dart';
import 'providers/keyword_wishlist_provider.dart';
import 'providers/keyword_price_provider.dart';
import 'services/analytics_service.dart';
import 'services/notification_service.dart';
import 'services/device_profile_sync.dart';
import 'theme/app_theme.dart';
import 'screens/main_screen.dart';
import 'screens/detail/product_detail_screen.dart';
import 'screens/search_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 3개를 병렬 실행 (모두 독립적)
  await Future.wait([
    initializeDateFormatting('ko_KR'),
    Hive.initFlutter(),
    Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
  ]);

  // Firestore 오프라인 퍼시스턴스: 두 번째 실행부터 로컬 캐시 우선 반환
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  // SWR용 Hive box 사전 오픈
  await Hive.openBox('feed_cache');

  runApp(const ProviderScope(child: TteolgaApp()));
}

class TteolgaApp extends ConsumerStatefulWidget {
  const TteolgaApp({super.key});

  @override
  ConsumerState<TteolgaApp> createState() => _TteolgaAppState();
}

class _TteolgaAppState extends ConsumerState<TteolgaApp> {
  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _initializeServices(); // fire-and-forget (비차단)
      _setupNotificationHandlers();
      _checkFirstPermission();
      _triggerDailyKeywordCollection();

      // DEBUG: 테스트 알림 발송 (3초 후)
      assert(() {
        Future.delayed(const Duration(seconds: 3), () {
          NotificationService().sendTestNotifications();
        });
        return true;
      }());
    }
  }

  Future<void> _initializeServices() async {
    try {
      final notiService = NotificationService();
      // DeviceProfileSync는 알림 초기화와 독립적이므로 병렬 시작
      final deviceFuture = DeviceProfileSync().initialize();

      await notiService.initialize();
      // 권한 요청과 토픽 구독은 순서가 필요하지만 DeviceProfileSync와는 병렬
      await notiService.requestPermission();
      await notiService.subscribeInitialTopics();

      await deviceFuture;

      // 초기 user property 설정
      final isDark = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
      AnalyticsService.setThemeProperty(isDark);
    } catch (e) {
      debugPrint('[Init] Service initialization error: $e');
    }
  }

  void _checkFirstPermission() async {
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      ref.read(notificationSettingsProvider.notifier).enableAllOnFirstPermission();
    }
  }

  /// 일별 키워드 가격 수집 트리거
  void _triggerDailyKeywordCollection() {
    // 앱 시작 후 5초 지연 (초기화 완료 대기)
    Future.delayed(const Duration(seconds: 5), () {
      if (!mounted) return;
      final wishItems = ref.read(keywordWishlistProvider);
      if (wishItems.isEmpty) return;

      final tracker = ref.read(keywordPriceTrackerProvider);
      tracker.collectSnapshots(wishItems).then((_) {
        debugPrint('[KeywordTracker] 일별 수집 완료');
      }).catchError((e) {
        debugPrint('[KeywordTracker] 일별 수집 실패: $e');
      });
    });
  }

  void _setupNotificationHandlers() {
    // 앱이 종료 상태에서 알림 탭으로 열렸을 때
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) _handleNotificationTap(message.data);
    });

    // 앱이 백그라운드 상태에서 알림 탭했을 때
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleNotificationTap(message.data);
    });

    // 포그라운드 로컬 알림 탭 콜백 등록
    NotificationService().setOnNotificationTap(_handleNotificationTap);

    // 딥링크 처리
    _setupDeepLinks();
  }

  void _setupDeepLinks() {
    final appLinks = AppLinks();

    // 앱이 종료 상태에서 딥링크로 열렸을 때
    appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleDeepLink(uri);
    });

    // 앱이 실행 중일 때 딥링크 수신
    appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    });
  }

  void _handleDeepLink(Uri uri) {
    // https://gooddeal-app.web.app/product/{productId}
    final segments = uri.pathSegments;
    if (segments.length >= 2 && segments[0] == 'product') {
      final productId = segments[1];
      if (productId.isNotEmpty) {
        AnalyticsService.logDeepLinkOpened(productId);
        _navigateToProduct(productId);
      }
    }
  }

  void _handleNotificationTap(Map<String, dynamic> data) {
    final productId = data['productId'] as String?;
    AnalyticsService.logNotificationTap(productId);
    // 키워드 알림 처리: payload가 "keyword:검색어" 형태
    if (productId != null && productId.startsWith('keyword:')) {
      final keyword = productId.substring(8);
      if (keyword.isNotEmpty) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => SearchScreen(initialQuery: keyword),
          ),
        );
        return;
      }
    }

    if (productId == null || productId.isEmpty) return;
    _navigateToProduct(productId);
  }

  static final _validProductId = RegExp(r'^[\w\-:.]{1,128}$');

  Future<void> _navigateToProduct(String productId) async {
    if (!_validProductId.hasMatch(productId)) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('products')
          .doc(productId)
          .get();

      if (!doc.exists || doc.data() == null) return;

      final product = Product.fromJson(doc.data()!);
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => ProductDetailScreen(product: product),
        ),
      );
    } catch (e) {
      debugPrint('[Notification] 상품 조회 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tteolgaThemeProvider);

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: '굿딜',
      debugShowCheckedModeBanner: false,
      theme: t.toThemeData(),
      navigatorObservers: [
        FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance),
      ],
      home: const MainScreen(),
    );
  }
}
