import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../providers/admin_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/screen_header.dart';

class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tteolgaThemeProvider);
    final topPadding = MediaQuery.of(context).padding.top;
    final statsAsync = ref.watch(adminStatsProvider);

    return Scaffold(
      backgroundColor: t.bg,
      body: statsAsync.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: t.textTertiary),
        ),
        error: (e, _) => Center(
          child: Text('Error: $e',
              style: TextStyle(color: t.textSecondary, fontSize: 14)),
        ),
        data: (stats) => ListView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16, topPadding + 8, 16, 40),
          children: [
            ScreenHeader(theme: t, title: 'Admin'),
            const SizedBox(height: 16),
            _buildLastUpdated(t, stats),
            const SizedBox(height: 16),
            _sectionLabel(t, 'Users'),
            const SizedBox(height: 8),
            _buildUserSection(t, stats),
            const SizedBox(height: 20),
            _sectionLabel(t, 'Banners'),
            const SizedBox(height: 8),
            _buildBannerSection(t, stats),
            const SizedBox(height: 20),
            _sectionLabel(t, 'Products'),
            const SizedBox(height: 8),
            _buildProductSection(t, stats),
            const SizedBox(height: 20),
            _sectionLabel(t, 'Notifications'),
            const SizedBox(height: 8),
            _buildNotificationSection(t, stats),
            const SizedBox(height: 20),
            _sectionLabel(t, 'Wishlist'),
            const SizedBox(height: 8),
            _buildWishlistSection(t, stats),
          ],
        ),
      ),
    );
  }

  Widget _buildLastUpdated(TteolgaTheme t, AdminStats stats) {
    final text = stats.updatedAt != null
        ? DateFormat('yyyy-MM-dd HH:mm').format(stats.updatedAt!)
        : '-';
    return Text(
      'Last updated: $text',
      style: TextStyle(color: t.textTertiary, fontSize: 12),
      textAlign: TextAlign.right,
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

  Widget _buildUserSection(TteolgaTheme t, AdminStats stats) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(t),
      child: Column(
        children: [
          _metricRow(t, 'Total Users', _fmt(stats.totalUsers)),
          const SizedBox(height: 10),
          Row(
            children: [
              _metricChip(t, 'iOS', _fmt(stats.iosUsers)),
              const SizedBox(width: 8),
              _metricChip(t, 'Android', _fmt(stats.androidUsers)),
            ],
          ),
          Divider(color: t.border, height: 24),
          _metricRow(t, 'Active Today', _fmt(stats.activeToday)),
          _metricRow(t, 'Active 7d', _fmt(stats.active7d)),
          _metricRow(t, 'Active 30d', _fmt(stats.active30d)),
        ],
      ),
    );
  }

  Widget _buildBannerSection(TteolgaTheme t, AdminStats stats) {
    final banners = stats.banners;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    int val(String key) => (banners[key] as num?)?.toInt() ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(t),
      child: Column(
        children: [
          _metricRow(t, 'Coupang Total', _fmt(val('coupangTotal'))),
          _metricRow(t, 'Coupang Today', _fmt(val('coupang_$today'))),
          Divider(color: t.border, height: 24),
          _metricRow(t, 'Announcement Impression',
              _fmt(val('announcement_impressionTotal'))),
          _metricRow(
              t, 'Announcement CTA', _fmt(val('announcement_ctaTotal'))),
          _metricRow(t, 'Announcement Close',
              _fmt(val('announcement_closeTotal'))),
        ],
      ),
    );
  }

  Widget _buildProductSection(TteolgaTheme t, AdminStats stats) {
    final sorted = stats.productsBySource.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(t),
      child: Column(
        children: [
          _metricRow(t, 'Total Products', _fmt(stats.totalProducts)),
          if (sorted.isNotEmpty) ...[
            Divider(color: t.border, height: 24),
            ...sorted.map(
                (e) => _metricRow(t, e.key, _fmt(e.value))),
          ],
        ],
      ),
    );
  }

  Widget _buildNotificationSection(TteolgaTheme t, AdminStats stats) {
    final sorted = stats.notificationsByType.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(t),
      child: Column(
        children: [
          _metricRow(t, 'Last 24h', _fmt(stats.notificationsLast24h)),
          if (sorted.isNotEmpty) ...[
            Divider(color: t.border, height: 24),
            ...sorted.map(
                (e) => _metricRow(t, e.key, _fmt(e.value))),
          ],
        ],
      ),
    );
  }

  Widget _buildWishlistSection(TteolgaTheme t, AdminStats stats) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(t),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _metricRow(t, 'Total Keyword Items', _fmt(stats.wishlistTotalItems)),
          if (stats.topKeywords.isNotEmpty) ...[
            Divider(color: t.border, height: 24),
            Text('Top Keywords',
                style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...stats.topKeywords.map((kw) {
              final keyword = kw['keyword'] as String? ?? '';
              final count = (kw['count'] as num?)?.toInt() ?? 0;
              return _metricRow(t, keyword, _fmt(count));
            }),
          ],
        ],
      ),
    );
  }

  Widget _metricRow(TteolgaTheme t, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(label,
                style: TextStyle(color: t.textSecondary, fontSize: 14),
                overflow: TextOverflow.ellipsis),
          ),
          Text(value,
              style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _metricChip(TteolgaTheme t, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(color: t.textTertiary, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  String _fmt(int n) => NumberFormat('#,###').format(n);
}
