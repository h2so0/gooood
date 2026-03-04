import 'dart:async';
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
import 'constants/app_constants.dart';
import 'models/product.dart';
import 'providers/notification_provider.dart';
import 'providers/keyword_wishlist_provider.dart';
import 'providers/keyword_price_provider.dart';
import 'services/analytics_service.dart';
import 'services/notification_service.dart';
import 'services/device_profile_sync.dart';
import 'services/startup_popup_service.dart';
import 'theme/app_theme.dart';
import 'screens/main_screen.dart';
import 'screens/detail/product_detail_screen.dart';
import 'screens/search_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
bool _firebaseInitialized = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 3개를 병렬 실행 (모두 독립적)
  try {
    await Future.wait([
      initializeDateFormatting('ko_KR'),
      Hive.initFlutter(),
      Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
          .then((_) => _firebaseInitialized = true),
    ]);

    // Firestore 오프라인 퍼시스턴스: 두 번째 실행부터 로컬 캐시 우선 반환
    if (_firebaseInitialized) {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: 50 * 1024 * 1024, // 50 MB
      );
    }

    // SWR용 Hive box 사전 오픈
    await Hive.openBox('feed_cache');
  } catch (e) {
    debugPrint('[Init] Initialization error: $e');
  }

  // 스플래시 중 Firestore pre-fetch (fire-and-forget)
  if (_firebaseInitialized) {
    _prefetchHotProducts();
  }

  runApp(const ProviderScope(child: TteolgaApp()));
}

/// 스플래시 중 Firestore 쿼리를 미리 실행해 SDK 내부 캐시 워밍업 (fire-and-forget)
void _prefetchHotProducts() {
  FirebaseFirestore.instance
      .collection('products')
      .where('feedOrder', isGreaterThanOrEqualTo: 0)
      .orderBy('feedOrder')
      .limit(PaginationConfig.pageSize)
      .get()
      .then((_) {})
      .catchError((e) {
    debugPrint('[Prefetch] hot products fetch error: $e');
  });
}

class TteolgaApp extends ConsumerStatefulWidget {
  const TteolgaApp({super.key});

  @override
  ConsumerState<TteolgaApp> createState() => _TteolgaAppState();
}

class _TteolgaAppState extends ConsumerState<TteolgaApp>
    with WidgetsBindingObserver {
  Timer? _keywordCollectionTimer;
  StreamSubscription<Uri>? _deepLinkSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!kIsWeb && _firebaseInitialized) {
      _initializeServices(); // fire-and-forget (비차단)
      _setupNotificationHandlers();
      _checkFirstPermission();
      _triggerDailyKeywordCollection();
    }
  }

  @override
  void dispose() {
    _keywordCollectionTimer?.cancel();
    _deepLinkSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    ref.read(platformBrightnessProvider.notifier).state =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
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

      // 서버 알림 내역 동기화 (fire-and-forget)
      notiService.syncFromServer();

      // 시작 팝업 (공지/업데이트) 표시
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      _showStartupPopup();
    } catch (e) {
      debugPrint('[Init] Service initialization error: $e');
    }
  }

  void _showStartupPopup() {
    final ctx = navigatorKey.currentContext;
    if (ctx != null) {
      StartupPopupService.checkAndShow(ctx, ref);
    }
  }

  void _checkFirstPermission() async {
    try {
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        ref.read(notificationSettingsProvider.notifier).enableAllOnFirstPermission();
      }
    } catch (e) {
      debugPrint('[Init] _checkFirstPermission error: $e');
    }
  }

  /// 일별 키워드 가격 수집 트리거
  void _triggerDailyKeywordCollection() {
    // 앱 시작 후 5초 지연 (초기화 완료 대기)
    _keywordCollectionTimer = Timer(const Duration(seconds: 5), () {
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
      if (message != null) {
        NotificationService().saveToHistoryIfNotDuplicate(message);
        _handleNotificationTap(message.data);
      }
    });

    // 앱이 백그라운드 상태에서 알림 탭했을 때
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      NotificationService().saveToHistoryIfNotDuplicate(message);
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
    _deepLinkSub = appLinks.uriLinkStream.listen((uri) {
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

  /// 탭 이름 목록 (MainScreen._tabs와 동일 순서)
  static const _tabNames = [
    '홈', '타임딜',
    '디지털/가전', '패션/의류', '생활/건강', '식품', '뷰티', '스포츠/레저', '출산/육아',
  ];

  int _resolveTabIndex(Product product) {
    // 타임딜: saleEndDate가 미래이면 타임딜 탭
    if (product.saleEndDate != null) {
      try {
        if (DateTime.parse(product.saleEndDate!).isAfter(DateTime.now())) {
          return 1;
        }
      } catch (_) {}
    }
    // 카테고리 매핑
    final cat = product.category1;
    if (cat.isNotEmpty) {
      for (int i = 2; i < _tabNames.length; i++) {
        if (_tabNames[i] == cat) return i;
      }
    }
    return 0; // 기본: 홈
  }

  Future<void> _navigateToProduct(String productId) async {
    if (!_validProductId.hasMatch(productId)) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('products')
          .doc(productId)
          .get();

      if (!doc.exists || doc.data() == null) return;

      final product = Product.fromJson(doc.data()!);

      // 해당 탭으로 전환
      final tabIndex = _resolveTabIndex(product);
      ref.read(mainTabIndexProvider.notifier).state = tabIndex;

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
