import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'theme/app_theme.dart';
import 'screens/main_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  runApp(const ProviderScope(child: TteolgaApp()));
}

class TteolgaApp extends ConsumerWidget {
  const TteolgaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tteolgaThemeProvider);

    return MaterialApp(
      title: 'tteolga',
      debugShowCheckedModeBanner: false,
      theme: t.toThemeData(),
      home: const MainScreen(),
    );
  }
}
