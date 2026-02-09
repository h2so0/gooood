import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tteolgaThemeProvider);
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: t.bg,
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, topPadding + 8, 16, 40),
        children: [
          // Back
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: t.card,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.arrow_back_ios_new,
                    size: 16, color: t.textSecondary),
              ),
            ),
          ),
          const SizedBox(height: 24),

          Text('설정',
              style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 24),

          // Watchlist
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: t.border, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.favorite_border,
                        color: t.textPrimary, size: 18),
                    const SizedBox(width: 10),
                    Text('관심 상품',
                        style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text('0개',
                        style: TextStyle(
                            color: t.textTertiary, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text('등록된 관심 상품이 없습니다',
                      style:
                          TextStyle(color: t.textTertiary, fontSize: 13)),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Settings rows
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: t.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: t.border, width: 0.5),
            ),
            child: Column(
              children: [
                _Row(t: t, icon: Icons.notifications_none, label: '알림 설정'),
                Container(height: 0.5, color: t.border),
                _ThemeRow(t: t),
                Container(height: 0.5, color: t.border),
                _Row(t: t, icon: Icons.info_outline, label: '앱 정보'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text('v1.0.0',
                style: TextStyle(color: t.textTertiary, fontSize: 11)),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final TteolgaTheme t;
  final IconData icon;
  final String label;
  const _Row({required this.t, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: t.textSecondary, size: 20),
          const SizedBox(width: 14),
          Text(label,
              style: TextStyle(color: t.textPrimary, fontSize: 15)),
          const Spacer(),
          Icon(Icons.chevron_right, color: t.textTertiary, size: 18),
        ],
      ),
    );
  }
}

class _ThemeRow extends ConsumerWidget {
  final TteolgaTheme t;
  const _ThemeRow({required this.t});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = t.brightness == Brightness.dark;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        ref.read(themeModeProvider.notifier).state =
            isDark ? ThemeMode.light : ThemeMode.dark;
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(
              isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
              color: t.textSecondary,
              size: 20,
            ),
            const SizedBox(width: 14),
            Text('테마 변경',
                style: TextStyle(color: t.textPrimary, fontSize: 15)),
            const Spacer(),
            Text(isDark ? '다크' : '라이트',
                style: TextStyle(color: t.textTertiary, fontSize: 13)),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: t.textTertiary, size: 18),
          ],
        ),
      ),
    );
  }
}
