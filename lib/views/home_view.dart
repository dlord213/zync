import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/theme_provider.dart';
import '../providers/device_info_provider.dart';
import '../providers/activity_log_provider.dart';

class HomeView extends ConsumerWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final deviceInfoAsync = ref.watch(deviceInfoProvider);
    final activityLogAsync = ref.watch(activityLogProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Zync'),
        actions: [
          IconButton(
            icon: Icon(themeMode == ThemeMode.light ? Icons.dark_mode : Icons.light_mode),
            onPressed: () {
              ref.read(themeProvider.notifier).toggleTheme();
            },
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Column(
                children: [
                  deviceInfoAsync.when(
                    data: (info) => Text(
                      'Device: ${info.deviceName} (${info.osType})',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    loading: () => const CircularProgressIndicator(),
                    error: (err, stack) => Text('Error loading device info: $err'),
                  ),
                  const SizedBox(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.send_rounded),
                        label: const Text('Send'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(140, 50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () => context.push('/send'),
                      ),
                      const SizedBox(width: 20),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Receive'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(140, 50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () => context.push('/receive'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Recent Activity', style: Theme.of(context).textTheme.titleLarge),
                  TextButton(
                    onPressed: () => context.push('/history'),
                    child: const Text('View All'),
                  ),
                ],
              ),
            ),
          ),
          activityLogAsync.when(
            data: (logs) {
              if (logs.isEmpty) {
                return const SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Text('No recent activity.', style: TextStyle(color: Colors.grey)),
                    ),
                  ),
                );
              }
              // Only take top 10 items
              final displayedLogs = logs.take(10).toList();
              
              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final log = displayedLogs[index];
                    final isSent = log.type == 'sent';
                    final date = DateTime.fromMillisecondsSinceEpoch(log.timestamp);
                    final timeStr = DateFormat.yMMMd().add_jm().format(date);

                    return ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSent ? Colors.orange.withOpacity(0.2) : Colors.green.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isSent ? Icons.upload_rounded : Icons.download_rounded,
                          color: isSent ? Colors.orange : Colors.green,
                        ),
                      ),
                      title: Text(log.fileName, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${isSent ? "To" : "From"}: ${log.targetDeviceName}\n$timeStr'),
                      isThreeLine: true,
                    );
                  },
                  childCount: displayedLogs.length,
                ),
              );
            },
            loading: () => const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator())),
            error: (err, stack) => SliverToBoxAdapter(child: Center(child: Text('Error loading activity: $err'))),
          ),
        ],
      ),
    );
  }
}
