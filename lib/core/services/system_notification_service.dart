import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Service that triggers Android System Notification Bar (Status Bar / Heads-up)
/// and handles terminal logs for development & production verification.
class SystemNotificationService {
  static const MethodChannel _channel = MethodChannel('com.diu.ride/notifications');

  static Future<void> showNotification({
    required String title,
    required String body,
    String? id,
  }) async {
    // 1. Production Terminal Log for audit verification
    // ignore: avoid_print
    print('[DIU_NOTIFICATION_BAR] $title: $body');

    // 2. Invoke Android native notification bar if running on Android
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _channel.invokeMethod('showNotification', {
          'id': id ?? DateTime.now().millisecondsSinceEpoch.toString(),
          'title': title,
          'body': body,
        });
      } catch (e) {
        debugPrint('[SYSTEM_NOTIFICATION_BAR ERROR] $e');
      }
    }
  }
}
