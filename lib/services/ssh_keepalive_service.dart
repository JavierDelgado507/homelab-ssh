import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class SshKeepaliveService {
  static int _count = 0;

  // Pide en runtime los permisos necesarios para que el foreground service
  // funcione. Llamar una vez al arrancar la app (desde HostsScreen.initState).
  // Sin POST_NOTIFICATIONS (Android 13+) el servicio no puede arrancar y
  // Android mata la app al tabular. Sin exención de batería, el proceso se
  // congela en background aunque el servicio esté activo.
  static Future<void> requestPermissions() async {
    final notifPerm = await FlutterForegroundTask.checkNotificationPermission();
    if (notifPerm != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
  }

  static void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'homelab_ssh_bg',
        channelName: 'homelab-ssh activo',
        channelDescription:
            'Mantiene las sesiones SSH activas en segundo plano',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
      ),
    );
  }

  static Future<void> onConnect() async {
    _count++;
    if (_count == 1) {
      await FlutterForegroundTask.startService(
        serviceId: 1001,
        notificationTitle: 'homelab-ssh',
        notificationText: 'Sesión SSH activa en segundo plano',
      );
    } else {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'homelab-ssh',
        notificationText: '$_count sesiones SSH activas',
      );
    }
  }

  static Future<void> onDisconnect() async {
    if (_count > 0) _count--;
    if (_count == 0) {
      await FlutterForegroundTask.stopService();
    } else {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'homelab-ssh',
        notificationText: '$_count sesión${_count > 1 ? 'es' : ''} SSH activa${_count > 1 ? 's' : ''}',
      );
    }
  }
}
