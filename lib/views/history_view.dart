import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/activity_log_provider.dart';

class HistoryView extends ConsumerWidget {
  const HistoryView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activityLogAsync = ref.watch(activityLogProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Full Activity History'),
      ),
      body: activityLogAsync.when(
        data: (logs) {
          if (logs.isEmpty) {
            return const Center(child: Text("No activity yet."));
          }
          return ListView.builder(
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final log = logs[index];
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
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error loading history: $err')),
      ),
    );
  }
}
