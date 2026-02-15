import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';

class TapRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? trailing;
  final VoidCallback onTap;
  const TapRow({
    super.key,
    required this.icon,
    required this.label,
    this.trailing,
    required this.onTap,
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
                color: isDark
                    ? const Color(0xFFAAAAAA)
                    : const Color(0xFF555555),
                size: 20),
            const SizedBox(width: 14),
            Text(label,
                style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontSize: 15)),
            const Spacer(),
            if (trailing != null) ...[
              Text(trailing!,
                  style: TextStyle(
                      color: isDark
                          ? const Color(0xFF666666)
                          : const Color(0xFFAAAAAA),
                      fontSize: 13)),
              const SizedBox(width: 4),
            ],
            Icon(Icons.chevron_right,
                color: isDark
                    ? const Color(0xFF666666)
                    : const Color(0xFFAAAAAA),
                size: 18),
          ],
        ),
      ),
    );
  }
}

class ThemeToggleRow extends ConsumerWidget {
  const ThemeToggleRow({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tteolgaThemeProvider);
    final isDark = t.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
              isDark
                  ? Icons.dark_mode_outlined
                  : Icons.light_mode_outlined,
              color: t.textSecondary,
              size: 20),
          const SizedBox(width: 14),
          Text('다크 모드',
              style: TextStyle(color: t.textPrimary, fontSize: 15)),
          const Spacer(),
          SizedBox(
              height: 28,
              child: Switch.adaptive(
                value: isDark,
                activeColor: t.textPrimary,
                activeTrackColor: t.textTertiary,
                inactiveThumbColor: t.textTertiary,
                inactiveTrackColor: t.border,
                onChanged: (_) {
                  ref.read(themeModeProvider.notifier).toggle();
                },
              )),
        ],
      ),
    );
  }
}

class ToggleRow extends StatelessWidget {
  final TteolgaTheme t;
  final IconData icon;
  final String label;
  final String desc;
  final bool value;
  final ValueChanged<bool> onChanged;
  const ToggleRow({
    super.key,
    required this.t,
    required this.icon,
    required this.label,
    required this.desc,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: t.textSecondary, size: 20),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style:
                      TextStyle(color: t.textPrimary, fontSize: 15)),
              const SizedBox(height: 2),
              Text(desc,
                  style:
                      TextStyle(color: t.textTertiary, fontSize: 12)),
            ],
          )),
          const SizedBox(width: 8),
          SizedBox(
              height: 28,
              child: Switch.adaptive(
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
