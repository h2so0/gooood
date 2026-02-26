import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';

/// 가격대 필터 상태
final priceRangeProvider = StateProvider<(int?, int?)>((ref) => (null, null));

class PriceFilterButton extends ConsumerWidget {
  const PriceFilterButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tteolgaThemeProvider);
    final range = ref.watch(priceRangeProvider);
    final isActive = range.$1 != null || range.$2 != null;

    return GestureDetector(
      onTap: () => _showFilterSheet(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Icon(
          Icons.filter_list,
          size: 18,
          color: isActive ? t.drop : t.textTertiary,
        ),
      ),
    );
  }

  void _showFilterSheet(BuildContext context, WidgetRef ref) {
    final t = ref.read(tteolgaThemeProvider);
    final current = ref.read(priceRangeProvider);
    int? minPrice = current.$1;
    int? maxPrice = current.$2;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
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
                Text('가격대 필터',
                    style: TextStyle(
                        color: t.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('원하는 가격 범위를 설정하세요',
                    style: TextStyle(color: t.textTertiary, fontSize: 13)),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _PriceField(
                        label: '최소 가격',
                        value: minPrice,
                        theme: t,
                        onChanged: (v) =>
                            setSheetState(() => minPrice = v),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('~',
                          style:
                              TextStyle(color: t.textSecondary, fontSize: 18)),
                    ),
                    Expanded(
                      child: _PriceField(
                        label: '최대 가격',
                        value: maxPrice,
                        theme: t,
                        onChanged: (v) =>
                            setSheetState(() => maxPrice = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: t.border),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () {
                            ref.read(priceRangeProvider.notifier).state =
                                (null, null);
                            Navigator.of(ctx).pop();
                          },
                          child: Text('초기화',
                              style: TextStyle(
                                  color: t.textSecondary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
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
                            ref.read(priceRangeProvider.notifier).state =
                                (minPrice, maxPrice);
                            Navigator.of(ctx).pop();
                          },
                          child: const Text('적용',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PriceField extends StatefulWidget {
  final String label;
  final int? value;
  final TteolgaTheme theme;
  final ValueChanged<int?> onChanged;

  const _PriceField({
    required this.label,
    required this.value,
    required this.theme,
    required this.onChanged,
  });

  @override
  State<_PriceField> createState() => _PriceFieldState();
}

class _PriceFieldState extends State<_PriceField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
        text: widget.value != null ? widget.value.toString() : '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label,
            style: TextStyle(color: t.textTertiary, fontSize: 12)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: t.bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: t.border),
          ),
          child: TextField(
            keyboardType: TextInputType.number,
            style: TextStyle(color: t.textPrimary, fontSize: 15),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: '0',
              hintStyle: TextStyle(color: t.textTertiary),
              suffixText: '원',
              suffixStyle: TextStyle(color: t.textTertiary, fontSize: 13),
            ),
            controller: _controller,
            onChanged: (text) {
              final v = int.tryParse(text);
              widget.onChanged(v);
            },
          ),
        ),
      ],
    );
  }
}
