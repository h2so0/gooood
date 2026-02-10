import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../providers/viewed_products_provider.dart';
import '../../providers/notification_provider.dart';
import '../../services/notification_service.dart';
import '../notification_history_screen.dart';
import '../legal_screen.dart';
import '../../widgets/coupang_banner.dart';
import 'settings_widgets.dart';
import 'viewed_products_sheet.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tteolgaThemeProvider);
    final topPadding = MediaQuery.of(context).padding.top;
    final viewedCount = ref.watch(viewedProductsProvider).length;
    final noti = ref.watch(notificationSettingsProvider);
    final notifier = ref.read(notificationSettingsProvider.notifier);

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

          // 일반
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: cardDecoration(t),
            child: Column(
              children: [
                const ThemeToggleRow(),
                Container(height: 0.5, color: t.border),
                TapRow(
                  icon: Icons.history,
                  label: '내가 본 상품',
                  trailing: viewedCount > 0 ? '$viewedCount' : null,
                  onTap: () => _showViewedProducts(context, ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // 알림 설정
          _sectionLabel(t, '알림 설정'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: cardDecoration(t),
            child: Column(
              children: [
                ToggleRow(
                  t: t,
                  icon: Icons.local_fire_department_outlined,
                  label: '핫딜 알림',
                  desc: '할인율 높은 특가 상품이 등록되면 알려드려요',
                  value: noti.hotDeal,
                  onChanged: (_) => notifier.toggleHotDeal(),
                ),
                Container(height: 0.5, color: t.border),
                ToggleRow(
                  t: t,
                  icon: Icons.timer_outlined,
                  label: '특가 마감 임박',
                  desc: '관심 특가가 1시간 내 종료될 때 알려드려요',
                  value: noti.saleSoonEnd,
                  onChanged: (_) => notifier.toggleSaleSoonEnd(),
                ),
                Container(height: 0.5, color: t.border),
                ToggleRow(
                  t: t,
                  icon: Icons.emoji_events_outlined,
                  label: '오늘의 BEST',
                  desc: '매일 오전 인기 상품 TOP5를 알려드려요',
                  value: noti.dailyBest,
                  onChanged: (_) => notifier.toggleDailyBest(),
                ),
                if (!kIsWeb) ...[
                  Container(height: 0.5, color: t.border),
                  Builder(builder: (context) {
                    final unread =
                        NotificationService().getUnreadCount();
                    return TapRow(
                      icon: Icons.notifications_outlined,
                      label: '알림 내역',
                      trailing: unread > 0 ? '$unread' : null,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) =>
                                const NotificationHistoryScreen()),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          const CoupangBanner(),
          const SizedBox(height: 20),

          // 앱 정보
          _sectionLabel(t, '앱 정보'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: cardDecoration(t),
            child: Column(
              children: [
                TapRow(
                  icon: Icons.description_outlined,
                  label: '이용약관',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) =>
                            const LegalScreen(type: LegalType.terms)),
                  ),
                ),
                Container(height: 0.5, color: t.border),
                TapRow(
                  icon: Icons.shield_outlined,
                  label: '개인정보 처리방침',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const LegalScreen(
                            type: LegalType.privacy)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(TteolgaTheme t, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(text,
          style: TextStyle(
              color: t.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600)),
    );
  }

  void _showViewedProducts(BuildContext context, WidgetRef ref) {
    final t = ref.read(tteolgaThemeProvider);
    final products = ref.read(viewedProductsProvider);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) =>
          ViewedProductsSheet(products: products, theme: t),
    );
  }
}
