import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notifiche locali per l'app manager: avvisano quando un rider rientra, anche
/// se il manager ha l'app in secondo piano (purché il processo sia vivo).
///
/// Nota: la "vera" push con app completamente chiusa richiederebbe Firebase
/// Cloud Functions (server). Questa versione è gratuita e copre il caso reale
/// del banco pizzeria con l'app aperta o in background.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const String _channelId = 'rientri';
  static const String _channelName = 'Rientri rider';

  Future<void> init() async {
    if (_ready) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwin = DarwinInitializationSettings();
      await _plugin.initialize(
        settings: const InitializationSettings(android: android, iOS: darwin),
      );

      // Canale Android (obbligatorio da Android 8 per notifiche prioritarie).
      final androidImpl =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'Avvisi quando un rider rientra in pizzeria',
          importance: Importance.high,
        ),
      );
      await androidImpl?.requestNotificationsPermission();

      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);

      _ready = true;
    } catch (e) {
      debugPrint('NotificationService init error: $e');
    }
  }

  /// Mostra "X è rientrato". L'id basato sul nome evita notifiche doppione per
  /// lo stesso rider.
  Future<void> showRiderReturned(String riderName) async {
    if (!_ready) await init();
    try {
      await _plugin.show(
        id: riderName.hashCode & 0x7fffffff,
        title: 'Rider rientrato',
        body: '$riderName è rientrato in pizzeria',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('NotificationService show error: $e');
    }
  }
}
