import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';
import 'screens/main_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
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
      } catch (e) {
        debugPrint('[Init] NotificationService 초기화 실패: $e');
      }
    }
  } catch (e) {
    debugPrint('[Init] 앱 초기화 실패: $e');
  }

  runApp(const ProviderScope(child: TteolgaApp()));
}

class TteolgaApp extends ConsumerWidget {
  const TteolgaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tteolgaThemeProvider);

    return MaterialApp(
      title: '굿딜',
      debugShowCheckedModeBanner: false,
      theme: t.toThemeData(),
      home: const MainScreen(),
    );
  }
}
