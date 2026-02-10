import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/notification_service.dart';

class NotificationHistoryScreen extends ConsumerStatefulWidget {
  const NotificationHistoryScreen({super.key});

  @override
  ConsumerState<NotificationHistoryScreen> createState() =>
      _NotificationHistoryScreenState();
}

class _NotificationHistoryScreenState
    extends ConsumerState<NotificationHistoryScreen> {
  List<Map<String, dynamic>> _records = [];

  @override
  void initState() {
    super.initState();
    _loadAndMarkRead();
  }

  void _loadAndMarkRead() {
    final service = NotificationService();
    service.markAllAsRead();
    setState(() {
      _records = service.getHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tteolgaThemeProvider);
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: t.bg,
      body: Column(
        children: [
          // 헤더
          Padding(
            padding: EdgeInsets.fromLTRB(16, topPadding + 8, 16, 0),
            child: Row(
              children: [
                GestureDetector(
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
                const SizedBox(width: 14),
                Text('알림 내역',
                    style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                if (_records.isNotEmpty)
                  GestureDetector(
                    onTap: () async {
                      await NotificationService().clearHistory();
                      setState(() => _records = []);
                    },
                    child: Text('전체 삭제',
                        style:
                            TextStyle(color: t.textTertiary, fontSize: 13)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 목록
          Expanded(
            child: _records.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.notifications_none,
                            color: t.textTertiary, size: 48),
                        const SizedBox(height: 12),
                        Text('알림 내역이 없어요',
                            style: TextStyle(
                                color: t.textTertiary, fontSize: 14)),
                      ],
                    ),
                  )
                : ListView.separated(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                        16, 0, 16, MediaQuery.of(context).padding.bottom + 24),
                    itemCount: _records.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 0),
                    itemBuilder: (context, i) =>
                        _NotificationTile(record: _records[i], theme: t),
                  ),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final Map<String, dynamic> record;
  final TteolgaTheme theme;
  const _NotificationTile({required this.record, required this.theme});

  static final _dateFmt = DateFormat('M/d (E) HH:mm', 'ko_KR');

  IconData _iconForType(String type) {
    switch (type) {
      case 'hotDeal':
        return Icons.local_fire_department_outlined;
      case 'saleEnd':
        return Icons.timer_outlined;
      case 'dailyBest':
        return Icons.emoji_events_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'hotDeal':
        return const Color(0xFFE04040);
      case 'saleEnd':
        return const Color(0xFFFF9800);
      case 'dailyBest':
        return const Color(0xFF448AFF);
      default:
        return const Color(0xFF888888);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final type = record['type'] as String? ?? '';
    final title = record['title'] as String? ?? '';
    final body = record['body'] as String? ?? '';
    final timestamp = DateTime.tryParse(record['timestamp'] as String? ?? '');
    final timeStr = timestamp != null ? _dateFmt.format(timestamp) : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.border, width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _colorForType(type).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                Icon(_iconForType(type), color: _colorForType(type), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: t.textSecondary,
                          fontSize: 13,
                          height: 1.4)),
                ],
                const SizedBox(height: 6),
                Text(timeStr,
                    style: TextStyle(color: t.textTertiary, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
