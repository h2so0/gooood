import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../providers/viewed_products_provider.dart';
import '../../providers/notification_provider.dart';
import '../../services/notification_service.dart';
import 'notification_history_sheet.dart';
import '../legal_screen.dart';
import '../../services/device_profile_sync.dart';
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
          // 헤더: 뒤로가기 + 제목
          SizedBox(
            height: 38,
            child: Stack(
              children: [
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
                Center(
                  child: Text('설정',
                      style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          const CoupangBanner(),
          const SizedBox(height: 20),

          // 일반
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: cardDecoration(t),
            child: Column(
              children: [
                if (!kIsWeb) ...[
                  Builder(builder: (context) {
                    final unread =
                        NotificationService().getUnreadCount();
                    return TapRow(
                      icon: Icons.notifications_outlined,
                      label: '알림 내역',
                      trailing: unread > 0 ? '$unread' : null,
                      onTap: () => _showNotificationHistory(context),
                    );
                  }),
                  Container(height: 0.5, color: t.border),
                ],
                const ThemeToggleRow(),
                Container(height: 0.5, color: t.border),
                TapRow(
                  icon: Icons.history,
                  label: '내가 본 상품',
                  trailing: viewedCount > 0 ? '$viewedCount' : null,
                  onTap: () => _showViewedProducts(context),
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
                  onChanged: (_) => _guardToggleOff(
                    context, t, noti.hotDeal, '핫딜 알림',
                    notifier.toggleHotDeal,
                  ),
                ),
                Container(height: 0.5, color: t.border),
                ToggleRow(
                  t: t,
                  icon: Icons.timer_outlined,
                  label: '특가 마감 임박',
                  desc: '관심 특가가 1시간 내 종료될 때 알려드려요',
                  value: noti.saleSoonEnd,
                  onChanged: (_) => _guardToggleOff(
                    context, t, noti.saleSoonEnd, '특가 마감 임박',
                    notifier.toggleSaleSoonEnd,
                  ),
                ),
                Container(height: 0.5, color: t.border),
                ToggleRow(
                  t: t,
                  icon: Icons.emoji_events_outlined,
                  label: '오늘의 BEST',
                  desc: '매일 오전 인기 상품 TOP5를 알려드려요',
                  value: noti.dailyBest,
                  onChanged: (_) => _guardToggleOff(
                    context, t, noti.dailyBest, '오늘의 BEST',
                    notifier.toggleDailyBest,
                  ),
                ),
                Container(height: 0.5, color: t.border),
                ToggleRow(
                  t: t,
                  icon: Icons.trending_down_outlined,
                  label: '가격 하락 알림',
                  desc: '내가 본 상품의 가격이 떨어지면 알려드려요',
                  value: noti.priceDrop,
                  onChanged: (_) => _guardToggleOff(
                    context, t, noti.priceDrop, '가격 하락 알림',
                    notifier.togglePriceDrop,
                  ),
                ),
                Container(height: 0.5, color: t.border),
                ToggleRow(
                  t: t,
                  icon: Icons.category_outlined,
                  label: '관심 카테고리 핫딜',
                  desc: '자주 보는 카테고리의 새 핫딜을 알려드려요',
                  value: noti.categoryAlert,
                  onChanged: (_) => _guardToggleOff(
                    context, t, noti.categoryAlert, '관심 카테고리 핫딜',
                    notifier.toggleCategoryAlert,
                  ),
                ),
                Container(height: 0.5, color: t.border),
                ToggleRow(
                  t: t,
                  icon: Icons.auto_awesome_outlined,
                  label: '맞춤 데일리 추천',
                  desc: '관심사 기반 개인화 TOP 추천을 매일 받아요',
                  value: noti.smartDigest,
                  onChanged: (_) => _guardToggleOff(
                    context, t, noti.smartDigest, '맞춤 데일리 추천',
                    notifier.toggleSmartDigest,
                  ),
                ),
                Container(height: 0.5, color: t.border),
                TapRow(
                  icon: Icons.do_not_disturb_on_outlined,
                  label: '방해금지 시간',
                  trailing:
                      '${noti.quietStartHour.toString().padLeft(2, '0')}시~${noti.quietEndHour.toString().padLeft(2, '0')}시',
                  onTap: () => _showQuietHourPicker(context, ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

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

  /// ON→OFF 시 경고 다이얼로그, OFF→ON 시 즉시 실행
  void _guardToggleOff(
    BuildContext context,
    TteolgaTheme t,
    bool currentValue,
    String label,
    VoidCallback toggle,
  ) {
    // 꺼져있던 걸 켜는 건 바로 실행
    if (!currentValue) {
      toggle();
      return;
    }

    // 켜져있던 걸 끄려면 경고
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          '$label을(를) 끄시겠어요?',
          style: TextStyle(
            color: t.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          '알림을 끄면 할인 정보와 특가 소식을 놓칠 수 있어요.',
          style: TextStyle(color: t.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('취소',
                style: TextStyle(color: t.textTertiary, fontSize: 14)),
          ),
          TextButton(
            onPressed: () {
              toggle();
              Navigator.of(ctx).pop();
            },
            child: const Text('끄기',
                style: TextStyle(color: Color(0xFFE04040), fontSize: 14)),
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

  void _showNotificationHistory(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const NotificationHistorySheet(),
    );
  }

  void _showViewedProducts(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const ViewedProductsSheet(),
    );
  }

  void _showQuietHourPicker(BuildContext context, WidgetRef ref) {
    final noti = ref.read(notificationSettingsProvider);
    int startHour = noti.quietStartHour;
    int endHour = noti.quietEndHour;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final t = ref.read(tteolgaThemeProvider);
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              padding: EdgeInsets.fromLTRB(
                  24, 20, 24, MediaQuery.of(ctx).padding.bottom + 20),
              decoration: BoxDecoration(
                color: t.card,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('방해금지 시간',
                      style: TextStyle(
                          color: t.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('이 시간에는 맞춤 알림을 보내지 않아요',
                      style:
                          TextStyle(color: t.textTertiary, fontSize: 13)),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _HourSelector(
                          label: '시작',
                          hour: startHour,
                          theme: t,
                          onChanged: (h) =>
                              setSheetState(() => startHour = h),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('~',
                            style: TextStyle(
                                color: t.textSecondary, fontSize: 18)),
                      ),
                      Expanded(
                        child: _HourSelector(
                          label: '종료',
                          hour: endHour,
                          theme: t,
                          onChanged: (h) =>
                              setSheetState(() => endHour = h),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: t.textPrimary,
                        foregroundColor: t.bg,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        ref
                            .read(notificationSettingsProvider.notifier)
                            .setQuietHours(startHour, endHour);
                        DeviceProfileSync().syncNow();
                        Navigator.of(ctx).pop();
                      },
                      child: const Text('저장',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _HourSelector extends StatelessWidget {
  final String label;
  final int hour;
  final TteolgaTheme theme;
  final ValueChanged<int> onChanged;

  const _HourSelector({
    required this.label,
    required this.hour,
    required this.theme,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(color: t.textTertiary, fontSize: 12)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: t.bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: t.border),
          ),
          child: DropdownButton<int>(
            value: hour,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            dropdownColor: t.card,
            style: TextStyle(color: t.textPrimary, fontSize: 15),
            items: List.generate(24, (i) {
              return DropdownMenuItem(
                value: i,
                child: Text('${i.toString().padLeft(2, '0')}:00'),
              );
            }),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ],
    );
  }
}
