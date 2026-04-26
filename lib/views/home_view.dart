import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../main.dart';
import '../providers/theme_provider.dart';
import '../providers/device_info_provider.dart';
import '../providers/activity_log_provider.dart';
import '../models/activity_log.dart';

class HomeView extends ConsumerWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final deviceInfoAsync = ref.watch(deviceInfoProvider);
    final activityLogAsync = ref.watch(activityLogProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? ZyncTheme.amoledBlack
          : Theme.of(context).colorScheme.surface,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // --- OneUI-Style Large Collapsing AppBar ---
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            stretch: true,
            backgroundColor: isDark
                ? ZyncTheme.amoledBlack
                : Theme.of(context).colorScheme.surface,
            surfaceTintColor: Colors.transparent,
            actions: [
              IconButton(
                icon: Icon(
                  themeMode == ThemeMode.light
                      ? LucideIcons.moon
                      : LucideIcons.sun,
                  size: 22,
                ),
                onPressed: () => ref.read(themeProvider.notifier).toggleTheme(),
              ),
              const SizedBox(width: 8),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: 20,
                    bottom: 60,
                    right: 20,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      deviceInfoAsync.when(
                        data: (info) => Text(
                          info.deviceName,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        loading: () => Text(
                          'Loading...',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        error: (_, __) => Text(
                          'Unknown Device',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              title: const Text('Zync'),
              titlePadding: const EdgeInsetsDirectional.only(
                start: 20,
                bottom: 14,
              ),
            ),
          ),

          // --- Action Cards (Send / Receive) ---
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: _ActionCard(
                      icon: LucideIcons.send,
                      label: 'Send',
                      accentColor: ZyncTheme.orange,
                      dimColor: isDark
                          ? ZyncTheme.orangeDim
                          : Colors.orange.shade50,
                      onTap: () => context.push('/send'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ActionCard(
                      icon: LucideIcons.download,
                      label: 'Receive',
                      accentColor: ZyncTheme.green,
                      dimColor: isDark
                          ? ZyncTheme.greenDim
                          : Colors.green.shade50,
                      onTap: () => context.push('/receive'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // --- Instructions Section ---
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? ZyncTheme.surface : Colors.white,
                  borderRadius: BorderRadius.circular(ZyncTheme.radius),
                  border: Border.all(
                    color: ZyncTheme.orange.withOpacity(0.15),
                    width: 1.5,
                  ),
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          LucideIcons.info,
                          color: ZyncTheme.orange,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'How to use Zync',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '1. Ensure both devices are on the same Wi-Fi.\n'
                      '2. Tap "Send" on one device and choose a file.\n'
                      '3. Tap "Receive" on the other device and select the sender from the radar, or scan their QR code.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(height: 1.5),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? ZyncTheme.orangeDim
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            LucideIcons.zap,
                            color: ZyncTheme.orange,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Tip: For lightning fast transfer speeds, turn on your Mobile Hotspot and connect the receiver to it instead of your home Wi-Fi!',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    height: 1.4,
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // --- "Recent Activity" header ---
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Recent Activity',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  GestureDetector(
                    onTap: () => context.push('/history'),
                    child: Text(
                      'View all',
                      style: TextStyle(
                        color: ZyncTheme.orange,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // --- Activity log list ---
          activityLogAsync.when(
            data: (logs) {
              if (logs.isEmpty) {
                return SliverToBoxAdapter(
                  child: _EmptyState(
                    icon: LucideIcons.clipboardList,
                    message:
                        'No transfers yet.\nSend or receive a file to get started.',
                  ),
                );
              }
              final displayed = logs.take(10).toList();
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final log = displayed[index];
                    final isFirst = index == 0;
                    final isLast = index == displayed.length - 1;
                    return _ActivityTile(
                      log: log,
                      isFirst: isFirst,
                      isLast: isLast,
                      isDark: isDark,
                    );
                  }, childCount: displayed.length),
                ),
              );
            },
            loading: () => const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (err, _) => SliverToBoxAdapter(
              child: _EmptyState(
                icon: LucideIcons.circleAlert,
                message: 'Failed to load activity.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Action Card Widget ---
class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accentColor;
  final Color dimColor;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.accentColor,
    required this.dimColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 110,
        decoration: BoxDecoration(
          color: dimColor,
          borderRadius: BorderRadius.circular(ZyncTheme.radius),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accentColor, size: 22),
            ),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Activity Tile Widget ---
class _ActivityTile extends StatelessWidget {
  final ActivityLog log;
  final bool isFirst;
  final bool isLast;
  final bool isDark;

  const _ActivityTile({
    required this.log,
    required this.isFirst,
    required this.isLast,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final isSent = log.type == 'sent';
    final date = DateTime.fromMillisecondsSinceEpoch(log.timestamp);
    final timeStr = DateFormat.MMMd().add_jm().format(date);
    final accentColor = isSent ? ZyncTheme.orange : ZyncTheme.green;
    final dimColor = isSent
        ? (isDark ? ZyncTheme.orangeDim : Colors.orange.shade50)
        : (isDark ? ZyncTheme.greenDim : Colors.green.shade50);

    final radius = BorderRadius.vertical(
      top: isFirst
          ? const Radius.circular(ZyncTheme.radius)
          : const Radius.circular(8),
      bottom: isLast
          ? const Radius.circular(ZyncTheme.radius)
          : const Radius.circular(8),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: isDark ? ZyncTheme.surface : Colors.white,
        borderRadius: radius,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Icon badge
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: dimColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isSent ? LucideIcons.upload : LucideIcons.download,
                color: accentColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            // Text info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    log.fileName,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${isSent ? "To" : "From"} ${log.targetDeviceName}',
                    style: Theme.of(context).textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              timeStr,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Empty State Widget ---
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 32),
      child: Column(
        children: [
          Icon(icon, size: 48, color: ZyncTheme.textSecondary),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }
}
