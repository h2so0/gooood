import 'package:app_links/app_links.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
import 'services/notification_service.dart';
import 'services/device_profile_sync.dart';
import 'theme/app_theme.dart';
import 'screens/main_screen.dart';
import 'screens/detail/product_detail_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await initializeDateFormatting('ko_KR');
    await Hive.initFlutter();
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    if (!kIsWeb) {
      try {
        final notiService = NotificationService();
        await notiService.initialize();
        await notiService.requestPermission();
        await notiService.subscribeInitialTopics();
        await DeviceProfileSync().initialize();
      } catch (e) {
        debugPrint('[Init] NotificationService 초기화 실패: $e');
      }
    }
  } catch (e) {
    debugPrint('[Init] 앱 초기화 실패: $e');
  }

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
      _setupNotificationHandlers();
      _checkFirstPermission();

      // DEBUG: 테스트 알림 발송 (3초 후)
      assert(() {
        Future.delayed(const Duration(seconds: 3), () {
          NotificationService().sendTestNotifications();
        });
        return true;
      }());
    }
  }

  void _checkFirstPermission() async {
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      ref.read(notificationSettingsProvider.notifier).enableAllOnFirstPermission();
    }
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
        _navigateToProduct(productId);
      }
    }
  }

  void _handleNotificationTap(Map<String, dynamic> data) {
    final productId = data['productId'] as String?;
    if (productId == null || productId.isEmpty) return;

    _navigateToProduct(productId);
  }

  Future<void> _navigateToProduct(String productId) async {
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
      home: const MainScreen(),
    );
  }
}
