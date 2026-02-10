import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../providers/product_provider.dart';
import '../providers/notification_provider.dart';
import '../services/notification_service.dart';
import '../models/product.dart';
import 'product_detail_screen.dart';
import 'notification_history_screen.dart';
import 'legal_screen.dart';
import '../utils/image_helper.dart';

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
                width: 38, height: 38,
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

          // ── 일반 ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: _cardDeco(t),
            child: Column(
              children: [
                // 다크 모드
                const _ThemeToggleRow(),
                Container(height: 0.5, color: t.border),
                // 내가 본 상품
                _TapRow(
                  icon: Icons.history,
                  label: '내가 본 상품',
                  trailing: viewedCount > 0 ? '$viewedCount' : null,
                  onTap: () => _showViewedProducts(context, ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── 알림 설정 ──
          _sectionLabel(t, '알림 설정'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: _cardDeco(t),
            child: Column(
              children: [
                _ToggleRow(
                  t: t, icon: Icons.local_fire_department_outlined,
                  label: '핫딜 알림',
                  desc: '할인율 높은 특가 상품이 등록되면 알려드려요',
                  value: noti.hotDeal,
                  onChanged: (_) => notifier.toggleHotDeal(),
                ),
                Container(height: 0.5, color: t.border),
                _ToggleRow(
                  t: t, icon: Icons.timer_outlined,
                  label: '특가 마감 임박',
                  desc: '관심 특가가 1시간 내 종료될 때 알려드려요',
                  value: noti.saleSoonEnd,
                  onChanged: (_) => notifier.toggleSaleSoonEnd(),
                ),
                Container(height: 0.5, color: t.border),
                _ToggleRow(
                  t: t, icon: Icons.emoji_events_outlined,
                  label: '오늘의 BEST',
                  desc: '매일 오전 인기 상품 TOP5를 알려드려요',
                  value: noti.dailyBest,
                  onChanged: (_) => notifier.toggleDailyBest(),
                ),
                if (!kIsWeb) ...[
                  Container(height: 0.5, color: t.border),
                  Builder(builder: (context) {
                    final unread = NotificationService().getUnreadCount();
                    return _TapRow(
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
          const SizedBox(height: 28),

          // ── 앱 정보 ──
          _sectionLabel(t, '앱 정보'),
          const SizedBox(height: 8),

          // 약관/정책/문의
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: _cardDeco(t),
            child: Column(
              children: [
                _TapRow(
                  icon: Icons.description_outlined,
                  label: '이용약관',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const LegalScreen(type: LegalType.terms)),
                  ),
                ),
                Container(height: 0.5, color: t.border),
                _TapRow(
                  icon: Icons.shield_outlined,
                  label: '개인정보 처리방침',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const LegalScreen(type: LegalType.privacy)),
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
      child: Text(text, style: TextStyle(
          color: t.textSecondary, fontSize: 13,
          fontWeight: FontWeight.w600)),
    );
  }

  BoxDecoration _cardDeco(TteolgaTheme t) => BoxDecoration(
    color: t.card,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: t.border, width: 0.5),
  );

  void _showViewedProducts(BuildContext context, WidgetRef ref) {
    final t = ref.read(tteolgaThemeProvider);
    final products = ref.read(viewedProductsProvider);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ViewedProductsSheet(products: products, theme: t),
    );
  }

}

// ── 공용 위젯 ──

class _TapRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? trailing;
  final VoidCallback onTap;
  const _TapRow({
    required this.icon, required this.label,
    this.trailing, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final isDark = t.brightness == Brightness.dark;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(icon,
                color: isDark ? const Color(0xFFAAAAAA) : const Color(0xFF555555),
                size: 20),
            const SizedBox(width: 14),
            Text(label, style: TextStyle(
                color: isDark ? Colors.white : Colors.black, fontSize: 15)),
            const Spacer(),
            if (trailing != null) ...[
              Text(trailing!, style: TextStyle(
                  color: isDark ? const Color(0xFF666666) : const Color(0xFFAAAAAA),
                  fontSize: 13)),
              const SizedBox(width: 4),
            ],
            Icon(Icons.chevron_right,
                color: isDark ? const Color(0xFF666666) : const Color(0xFFAAAAAA),
                size: 18),
          ],
        ),
      ),
    );
  }
}

class _ThemeToggleRow extends ConsumerWidget {
  const _ThemeToggleRow();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tteolgaThemeProvider);
    final isDark = t.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
              color: t.textSecondary, size: 20),
          const SizedBox(width: 14),
          Text('다크 모드', style: TextStyle(
              color: t.textPrimary, fontSize: 15)),
          const Spacer(),
          SizedBox(height: 28, child: Switch.adaptive(
            value: isDark,
            activeColor: t.textPrimary,
            activeTrackColor: t.textTertiary,
            inactiveThumbColor: t.textTertiary,
            inactiveTrackColor: t.border,
            onChanged: (_) {
              ref.read(themeModeProvider.notifier).state =
                  isDark ? ThemeMode.light : ThemeMode.dark;
            },
          )),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final TteolgaTheme t;
  final IconData icon;
  final String label;
  final String desc;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ToggleRow({
    required this.t, required this.icon, required this.label,
    required this.desc, required this.value, required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: t.textSecondary, size: 20),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(
                  color: t.textPrimary, fontSize: 15)),
              const SizedBox(height: 2),
              Text(desc, style: TextStyle(
                  color: t.textTertiary, fontSize: 12)),
            ],
          )),
          const SizedBox(width: 8),
          SizedBox(height: 28, child: Switch.adaptive(
            value: value,
            activeColor: t.textPrimary,
            activeTrackColor: t.textTertiary,
            inactiveThumbColor: t.textTertiary,
            inactiveTrackColor: t.border,
            onChanged: onChanged,
          )),
        ],
      ),
    );
  }
}

// ── 내가 본 상품 모달 ──

class _ViewedProductsSheet extends StatelessWidget {
  final List<Product> products;
  final TteolgaTheme theme;
  const _ViewedProductsSheet({required this.products, required this.theme});

  static final _fmt = NumberFormat('#,###', 'ko_KR');

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final t = theme;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(width: 36, height: 4,
            decoration: BoxDecoration(
              color: t.textTertiary.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            )),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Text('내가 본 상품', style: TextStyle(
                  color: t.textPrimary, fontSize: 17,
                  fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Text('${products.length}', style: TextStyle(
                  color: t.textTertiary, fontSize: 14)),
            ]),
          ),
          const SizedBox(height: 12),
          Container(height: 0.5, color: t.border),
          if (products.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 60),
              child: Text('아직 본 상품이 없어요',
                  style: TextStyle(color: t.textTertiary, fontSize: 14)),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPadding + 16),
                itemCount: products.length,
                separatorBuilder: (_, __) => const SizedBox(height: 0),
                itemBuilder: (context, i) =>
                    _ViewedProductTile(product: products[i], theme: t),
              ),
            ),
        ],
      ),
    );
  }
}

class _ViewedProductTile extends StatelessWidget {
  final Product product;
  final TteolgaTheme theme;
  const _ViewedProductTile({required this.product, required this.theme});

  static final _fmt = NumberFormat('#,###', 'ko_KR');

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final p = product;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Navigator.of(context).pop();
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ProductDetailScreen(product: p)),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 56, height: 56,
                child: p.imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: proxyImage(p.imageUrl), fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: t.surface),
                        errorWidget: (_, __, ___) => Container(
                          color: t.surface,
                          child: Icon(Icons.shopping_bag_outlined,
                              color: t.textTertiary, size: 20)),
                      )
                    : Container(color: t.surface,
                        child: Icon(Icons.shopping_bag_outlined,
                            color: t.textTertiary, size: 20)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: t.textPrimary, fontSize: 14, height: 1.3)),
                const SizedBox(height: 4),
                Row(children: [
                  if (p.dropRate > 0) ...[
                    Text('${p.dropRate.toStringAsFixed(0)}%',
                        style: TextStyle(color: t.drop, fontSize: 14,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(width: 6),
                  ],
                  Text('${_fmt.format(p.currentPrice)}원',
                      style: TextStyle(color: t.textPrimary, fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ]),
              ],
            )),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: t.textTertiary, size: 18),
          ],
        ),
      ),
    );
  }
}
