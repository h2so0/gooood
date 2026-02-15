import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/product.dart';
import '../../theme/app_theme.dart';
import '../../services/notification_service.dart';
import '../detail/product_detail_screen.dart';

class NotificationHistorySheet extends ConsumerStatefulWidget {
  const NotificationHistorySheet({super.key});

  @override
  ConsumerState<NotificationHistorySheet> createState() =>
      _NotificationHistorySheetState();
}

class _NotificationHistorySheetState
    extends ConsumerState<NotificationHistorySheet> {
  List<Map<String, dynamic>> _records = [];

  @override
  void initState() {
    super.initState();
    final service = NotificationService();
    service.markAllAsRead();
    _records = service.getHistory();
  }

  Future<void> _onTileTap(Map<String, dynamic> record) async {
    final productId = record['productId'] as String?;
    if (productId == null || productId.isEmpty) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('products')
          .doc(productId)
          .get();

      if (!doc.exists || doc.data() == null) return;
      if (!mounted) return;

      final product = Product.fromJson(doc.data()!);
      Navigator.of(context).pop(); // 시트 닫기
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProductDetailScreen(product: product),
        ),
      );
    } catch (e) { debugPrint('[NotificationHistory] product load error: $e'); }
  }

  void _deleteRecord(int listIndex) async {
    final record = _records[listIndex];
    final boxIndex = record['_boxIndex'] as int?;
    if (boxIndex != null) {
      await NotificationService().deleteAt(boxIndex);
    }
    setState(() {
      _records.removeAt(listIndex);
      // box 인덱스가 변경되므로 다시 로드
      _records = NotificationService().getHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tteolgaThemeProvider);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

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
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: t.textTertiary.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Text('알림 내역',
                  style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Text('${_records.length}',
                  style: TextStyle(color: t.textTertiary, fontSize: 14)),
              const Spacer(),
              if (_records.isNotEmpty)
                GestureDetector(
                  onTap: () async {
                    await NotificationService().clearHistory();
                    setState(() => _records = []);
                  },
                  child: Text('전체삭제',
                      style: TextStyle(color: t.textTertiary, fontSize: 13)),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          Container(height: 0.5, color: t.border),
          if (_records.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 60),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.notifications_none,
                      color: t.textTertiary, size: 40),
                  const SizedBox(height: 10),
                  Text('알림 내역이 없어요',
                      style: TextStyle(color: t.textTertiary, fontSize: 14)),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(0, 4, 0, bottomPadding + 16),
                itemCount: _records.length,
                itemBuilder: (context, i) {
                  final record = _records[i];
                  return _SwipeToDeleteTile(
                    key: ValueKey(
                        '${record['timestamp']}_${record['title']}'),
                    record: record,
                    theme: t,
                    onTap: () => _onTileTap(record),
                    onDelete: () => _deleteRecord(i),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _SwipeToDeleteTile extends StatefulWidget {
  final Map<String, dynamic> record;
  final TteolgaTheme theme;
  final VoidCallback? onTap;
  final VoidCallback onDelete;

  const _SwipeToDeleteTile({
    super.key,
    required this.record,
    required this.theme,
    this.onTap,
    required this.onDelete,
  });

  @override
  State<_SwipeToDeleteTile> createState() => _SwipeToDeleteTileState();
}

class _SwipeToDeleteTileState extends State<_SwipeToDeleteTile>
    with SingleTickerProviderStateMixin {
  static const _deleteButtonWidth = 72.0;
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  bool _isOpen = false;

  static final _dateFmt = DateFormat('M/d (E) HH:mm', 'ko_KR');

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-_deleteButtonWidth, 0),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    _controller.value -= delta / _deleteButtonWidth;
  }

  void _handleDragEnd(DragEndDetails details) {
    if (_controller.value > 0.5) {
      _controller.forward();
      _isOpen = true;
    } else {
      _controller.reverse();
      _isOpen = false;
    }
  }

  void _close() {
    _controller.reverse();
    _isOpen = false;
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inHours < 1) return '${diff.inMinutes}분 전';
    if (diff.inDays < 1) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return _dateFmt.format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final record = widget.record;
    final title = record['title'] as String? ?? '';
    final body = record['body'] as String? ?? '';
    final timestamp =
        DateTime.tryParse(record['timestamp'] as String? ?? '');
    final timeStr = timestamp != null ? _relativeTime(timestamp) : '';
    final hasProduct =
        (record['productId'] as String?)?.isNotEmpty == true;

    return ClipRect(
      child: Stack(
        children: [
          // 삭제 버튼 (뒤쪽)
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: widget.onDelete,
                child: Container(
                  width: _deleteButtonWidth,
                  color: const Color(0xFFE04040),
                  alignment: Alignment.center,
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.delete_outline,
                          color: Colors.white, size: 20),
                      SizedBox(height: 2),
                      Text('삭제',
                          style: TextStyle(
                              color: Colors.white, fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // 콘텐츠 (앞쪽, 슬라이드)
          AnimatedBuilder(
            animation: _slideAnimation,
            builder: (context, child) {
              return Transform.translate(
                offset: _slideAnimation.value,
                child: child,
              );
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: _handleDragUpdate,
              onHorizontalDragEnd: _handleDragEnd,
              onTap: () {
                if (_isOpen) {
                  _close();
                } else {
                  widget.onTap?.call();
                }
              },
              child: Container(
                color: t.bg,
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                            const SizedBox(height: 3),
                            Text(body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: t.textSecondary,
                                    fontSize: 13,
                                    height: 1.3)),
                          ],
                          const SizedBox(height: 4),
                          Text(timeStr,
                              style: TextStyle(
                                  color: t.textTertiary, fontSize: 11)),
                        ],
                      ),
                    ),
                    if (hasProduct)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, left: 8),
                        child: Icon(Icons.chevron_right,
                            color: t.textTertiary, size: 18),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
