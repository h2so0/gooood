import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../utils/snackbar_helper.dart';
import '../../providers/keyword_wishlist_provider.dart';
import '../../services/analytics_service.dart';

class TargetPriceSheet extends ConsumerStatefulWidget {
  final String keyword;
  final int? currentTargetPrice;
  final int? currentMinPrice;

  const TargetPriceSheet({
    super.key,
    required this.keyword,
    this.currentTargetPrice,
    this.currentMinPrice,
  });

  @override
  ConsumerState<TargetPriceSheet> createState() => _TargetPriceSheetState();
}

class _TargetPriceSheetState extends ConsumerState<TargetPriceSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.currentTargetPrice?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tteolgaThemeProvider);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(24, 20, 24, 16 + bottomPadding),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 핸들
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: t.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          Text('목표 가격 설정',
              style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('이 가격 이하로 떨어지면 알려드려요',
              style: TextStyle(color: t.textTertiary, fontSize: 13)),
          const SizedBox(height: 20),

          if (widget.currentMinPrice != null && widget.currentMinPrice! > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                '현재 최저가: ${formatPrice(widget.currentMinPrice!)}',
                style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500),
              ),
            ),

          // 가격 입력
          Container(
            height: 50,
            decoration: BoxDecoration(
              color: t.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.border, width: 0.5),
            ),
            child: TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                prefixText: '\u20a9 ',
                prefixStyle: TextStyle(
                    color: t.textTertiary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600),
                hintText: '목표 가격 입력',
                hintStyle: TextStyle(color: t.textTertiary, fontSize: 16),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 퀵 할인 버튼
          if (widget.currentMinPrice != null && widget.currentMinPrice! > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _quickButton(t, '-10%',
                      (widget.currentMinPrice! * 0.9).toInt()),
                  const SizedBox(width: 8),
                  _quickButton(t, '-20%',
                      (widget.currentMinPrice! * 0.8).toInt()),
                  const SizedBox(width: 8),
                  _quickButton(t, '-30%',
                      (widget.currentMinPrice! * 0.7).toInt()),
                ],
              ),
            ),

          // 저장 버튼
          GestureDetector(
            onTap: _save,
            child: Container(
              width: double.infinity,
              height: 48,
              decoration: BoxDecoration(
                color: t.drop,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: const Text('저장',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ),
          ),

          // 해제 버튼
          if (widget.currentTargetPrice != null) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _clear,
              child: Container(
                width: double.infinity,
                height: 44,
                alignment: Alignment.center,
                child: Text('목표 가격 해제',
                    style:
                        TextStyle(color: t.textTertiary, fontSize: 14)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _quickButton(TteolgaTheme t, String label, int price) {
    return GestureDetector(
      onTap: () {
        _controller.text = price.toString();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: t.border, width: 0.5),
        ),
        child: Column(
          children: [
            Text(label,
                style: TextStyle(color: t.textSecondary, fontSize: 12)),
            Text(formatPrice(price),
                style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  void _save() {
    final text = _controller.text.trim();
    final price = int.tryParse(text);
    if (price == null || price <= 0) return;

    AnalyticsService.logTargetPriceSet(
        widget.keyword, price, widget.currentMinPrice);
    ref
        .read(keywordWishlistProvider.notifier)
        .updateTargetPrice(widget.keyword, price);
    Navigator.of(context).pop();
    showAppSnackBar(context, ref.read(tteolgaThemeProvider),
        '목표가 ${formatPrice(price)} 설정');
  }

  void _clear() {
    AnalyticsService.logTargetPriceCleared(widget.keyword);
    ref
        .read(keywordWishlistProvider.notifier)
        .updateTargetPrice(widget.keyword, null);
    Navigator.of(context).pop();
    showAppSnackBar(
        context, ref.read(tteolgaThemeProvider), '목표가 해제됨');
  }
}
