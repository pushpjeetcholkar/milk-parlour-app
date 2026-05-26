import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:workmanager/workmanager.dart';
import 'app.dart';
import 'services/google_drive_service.dart';

// ── WorkManager background task dispatcher ─────────────────────────────────
// Must be a top-level function annotated with @pragma('vm:entry-point')
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, _) async {
    if (task == kDailyDriveBackupTask) {
      // Silent Google Drive backup — no UI shown
      await GoogleDriveService.silentBackup();
    }
    return Future.value(true);
  });
}

/// The WorkManager task name for the daily backup.
const kDailyDriveBackupTask = 'hkmcDailyDriveBackup';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialise WorkManager (background task engine)
  await Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: false, // Set true during testing to see task logs
  );

  // Re-register the daily backup task if the user had it enabled
  // (WorkManager tasks survive reboots but need re-registration on cold start)
  final autoEnabled = await GoogleDriveService.isAutoBackupEnabled();
  if (autoEnabled) {
    await _registerDailyBackup();
  }

  runApp(const MilkParlourApp());
}

/// Registers (or replaces) the daily midnight Google Drive backup task.
Future<void> registerDailyBackupTask() => _registerDailyBackup();

Future<void> _registerDailyBackup() async {
  // Calculate delay until next midnight
  final now = DateTime.now();
  final nextMidnight = DateTime(now.year, now.month, now.day + 1);
  final initialDelay = nextMidnight.difference(now);

  await Workmanager().registerPeriodicTask(
    kDailyDriveBackupTask,
    kDailyDriveBackupTask,
    frequency: const Duration(hours: 24),
    initialDelay: initialDelay,
    constraints: Constraints(
      networkType: NetworkType.connected, // Only backup when internet is on
      requiresBatteryNotLow: true,
    ),
    existingWorkPolicy: ExistingWorkPolicy.replace,
  );
}

/// Cancels the daily backup task.
Future<void> cancelDailyBackupTask() async {
  await Workmanager().cancelByUniqueName(kDailyDriveBackupTask);
}
