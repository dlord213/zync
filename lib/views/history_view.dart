import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../main.dart';
import '../providers/activity_log_provider.dart';
import '../models/activity_log.dart';

class HistoryView extends ConsumerWidget {
  const HistoryView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activityLogAsync = ref.watch(activityLogProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? ZyncTheme.amoledBlack
          : Theme.of(context).colorScheme.surface,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // --- Large Collapsing AppBar ---
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            stretch: true,
            backgroundColor: isDark
                ? ZyncTheme.amoledBlack
                : Theme.of(context).colorScheme.surface,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(LucideIcons.arrowLeft),
              onPressed: () => Navigator.of(context).pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 20, bottom: 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'History',
                        style: Theme.of(context).textTheme.displayLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Recent transfers',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // --- List content ---
          activityLogAsync.when(
            data: (logs) {
              if (logs.isEmpty) {
                return SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          LucideIcons.clipboardList,
                          size: 52,
                          color: ZyncTheme.textSecondary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No transfers yet.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final log = logs[index];
                    final isFirst = index == 0;
                    final isLast = index == logs.length - 1;
                    return _HistoryTile(
                      log: log,
                      isFirst: isFirst,
                      isLast: isLast,
                      isDark: isDark,
                    );
                  }, childCount: logs.length),
                ),
              );
            },
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (err, _) => SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      LucideIcons.circleAlert,
                      size: 48,
                      color: ZyncTheme.textSecondary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load history',
                      style: Theme.of(context).textTheme.bodyMedium,
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

class _HistoryTile extends StatelessWidget {
  final ActivityLog log;
  final bool isFirst;
  final bool isLast;
  final bool isDark;

  const _HistoryTile({
    required this.log,
    required this.isFirst,
    required this.isLast,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final isSent = log.type == 'sent';
    final date = DateTime.fromMillisecondsSinceEpoch(log.timestamp);
    final timeStr = DateFormat.yMMMd().add_jm().format(date);
    final accentColor = isSent ? ZyncTheme.orange : ZyncTheme.green;
    final dimColor = isSent
        ? (isDark ? ZyncTheme.orangeDim : Colors.orange.shade50)
        : (isDark ? ZyncTheme.greenDim : Colors.green.shade50);

    final borderRadius = BorderRadius.vertical(
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
        borderRadius: borderRadius,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
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
