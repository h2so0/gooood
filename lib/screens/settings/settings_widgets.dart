import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_theme.dart';
import '../../providers/notification_provider.dart';
import '../../services/device_profile_sync.dart';

class TapRow extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tteolgaThemeProvider);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: t.textSecondary, size: 20),
            const SizedBox(width: 14),
            Text(label,
                style: TextStyle(color: t.textPrimary, fontSize: 15)),
            const Spacer(),
            if (trailing != null) ...[
              Text(trailing!,
                  style: TextStyle(color: t.textTertiary, fontSize: 13)),
              const SizedBox(width: 4),
            ],
            Icon(Icons.chevron_right,
                color: t.textTertiary, size: 18),
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
                activeThumbColor: t.textPrimary,
                activeTrackColor: t.textTertiary,
                inactiveThumbColor: t.textTertiary,
                inactiveTrackColor: t.border,
                onChanged: (_) {
                  ref.read(themeModeProvider.notifier).toggle();
                  final newIsDark = !isDark;
                  AnalyticsService.logThemeToggle(newIsDark);
                  AnalyticsService.setThemeProperty(newIsDark);
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
                activeThumbColor: t.textPrimary,
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

class HourSelector extends StatelessWidget {
  final String label;
  final int hour;
  final TteolgaTheme theme;
  final ValueChanged<int> onChanged;

  const HourSelector({
    super.key,
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

void showQuietHourPicker(BuildContext context, WidgetRef ref) {
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
                      child: HourSelector(
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
                      child: HourSelector(
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
