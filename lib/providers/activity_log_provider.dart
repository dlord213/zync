import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/activity_log.dart';
import '../services/database_service.dart';

class ActivityLogNotifier extends AsyncNotifier<List<ActivityLog>> {
  @override
  Future<List<ActivityLog>> build() async {
    return _fetchLogs();
  }

  Future<List<ActivityLog>> _fetchLogs() async {
    return await DatabaseService().getLogs();
  }

  Future<void> addLog(ActivityLog log) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await DatabaseService().insertLog(log);
      return _fetchLogs();
    });
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      return _fetchLogs();
    });
  }
}

final activityLogProvider = AsyncNotifierProvider<ActivityLogNotifier, List<ActivityLog>>(() {
  return ActivityLogNotifier();
});
