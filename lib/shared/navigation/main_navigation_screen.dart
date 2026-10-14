import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/network/websocket_client.dart';
import 'package:diu_ride/features/chat/presentation/screens/campus_messages_screen.dart';
import 'package:diu_ride/features/chat/presentation/screens/chat_screen.dart';
import 'package:diu_ride/features/home/presentation/screens/home_screen.dart';
import 'package:diu_ride/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:diu_ride/features/notifications/presentation/providers/notifications_provider.dart';
import 'package:diu_ride/features/profile/presentation/screens/profile_screen.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';
import 'package:diu_ride/features/rides/presentation/screens/all_shared_rides_screen.dart';
import 'package:diu_ride/features/rides/presentation/screens/offer_ride_screen.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/booking/presentation/providers/booking_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:diu_ride/core/config/app_config.dart';
import 'package:diu_ride/core/services/system_notification_service.dart';
import 'package:diu_ride/features/notifications/data/models/notification_model.dart';
import 'package:diu_ride/core/services/notification_sound_service.dart';
import 'package:diu_ride/features/rides/presentation/widgets/post_expiry_extension_dialog.dart';
import 'package:diu_ride/shared/widgets/diu_app_header.dart';
import 'package:diu_ride/shared/widgets/diu_bottom_nav.dart';

class MainNavigationScreen extends ConsumerStatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  ConsumerState<MainNavigationScreen> createState() =>
      _MainNavigationScreenState();
}

class _MainNavigationScreenState extends ConsumerState<MainNavigationScreen> {
  int _currentTab = 0;
  int _unreadChatCount = 0;
  StreamSubscription? _wsSubscription;

  // Tab index mapping:
  // 0 → Home
  // 1 → All Shared Rides (Location filters, price sort, card details)
  // 2 → Offer Ride (Create bike ride)
  // 3 → Campus SMS & Community Messages
  // 4 → Profile

  final List<String> _titles = [
    'Home',
    'All Shared Rides',
    'Offer Ride',
    'Campus Messages',
    'Profile',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupWebSocketLiveUpdates();
      _syncInitialVarsityNotices();
    });
  }

  void _syncInitialVarsityNotices() async {
    try {
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 4)));
      final apiBase = kIsWeb ? '${Uri.base.origin}/ride/api' : AppConfig.current.apiBaseUrl;
      await ref.read(notificationsProvider.notifier).syncNoticesFromServer(dio, apiBase);
    } catch (_) {}
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    NotificationSoundService.stopRinging();
    super.dispose();
  }

  void _setupWebSocketLiveUpdates() {
    try {
      final wsClient = ref.read(webSocketClientProvider);
      _wsSubscription?.cancel();
      _wsSubscription = wsClient.messages.listen((msg) {
        final event = msg['event'] ?? msg['type'];
        final data = msg['data'] is Map ? Map<String, dynamic>.from(msg['data'] as Map) : msg;

        // 1. Live rides updates (New ride published, booked, started, or completed)
        if (event == 'ride_created' ||
            event == 'new_ride' ||
            event == 'ride_updated' ||
            event == 'ride_started' ||
            event == 'ride_completed' ||
            event == 'ride_cancelled' ||
            event == 'booking_created' ||
            event == 'booking_status_updated') {
          debugPrint('[Live WS] Received $event - refreshing live rides cache');
          ref.invalidate(allAvailableRidesProvider);
          ref.invalidate(departingSoonRidesProvider);
          ref.invalidate(myBookingsProvider);
        }

        // 1b. Live ride booking request alert for rider
        if (event == 'ride_booking_request') {
          _handleRideBookingRequest(data);
        }

        // 1c. Live booking accepted alert for passenger
        if (event == 'ride_booking_accepted') {
          _handleRideBookingAccepted(data);
        }

        // 1d. Ride session status changed (Confirm / Cancel / Complete)
        if (event == 'ride_session_status_changed') {
          _handleRideSessionStatusChanged(data);
        }

        // 2. Live student requests (Requested or accepted by biker)
        if (event == 'passenger_request_created' ||
            event == 'new_passenger_request' ||
            event == 'passenger_request_accepted') {
          debugPrint('[Live WS] Received $event - refreshing passenger requests');
          ref.invalidate(passengerRequestsProvider);
        }

        // 3. Urgent dedicated alert ring buzzer
        if (event == 'alert_ring') {
          _showAlertRingBuzzer(data);
        }

        // 4. Remote stop ring signal from caller
        if (event == 'stop_ring') {
          _handleRemoteStopRing(data);
        }

        // 5. Live incoming chat message notification
        if (event == 'chat_message') {
          _handleIncomingChatMessage(data);
        }

        // 6. University Varsity Authority Notice
        if (event == 'university_notice' || event == 'announcement') {
          _handleUniversityNotice(data);
        }

        // 7. Scheduled ride / request time arrived - prompt extension
        if (event == 'schedule_time_expired_needs_extension') {
          _handleScheduleTimeExpiredNeedsExtension(data);
        }

        // 8. Post expired and deleted from server/database
        if (event == 'post_expired_and_deleted') {
          _handlePostExpiredAndDeleted(data);
        }
      });
    } catch (e) {
      debugPrint('[MainNavigation] WebSocket live update init error: $e');
    }
  }

  void _handleScheduleTimeExpiredNeedsExtension(Map<String, dynamic> data) {
    if (!mounted) return;
    final currentAuth = ref.read(authNotifierProvider).user;
    if (currentAuth == null) return;

    final targetUserId = (data['userId'] ?? '').toString().trim();
    final targetUserName = (data['userName'] ?? '').toString().trim();
    final isOwner = targetUserId.isNotEmpty && (
      targetUserId == currentAuth.id ||
      targetUserId == currentAuth.studentId ||
      (currentAuth.phone.isNotEmpty && targetUserId == currentAuth.phone) ||
      (targetUserName.isNotEmpty && targetUserName.toLowerCase() == currentAuth.name.toLowerCase())
    );

    if (!isOwner) return;

    final postId = (data['id'] ?? '').toString();
    final postType = (data['post_type'] ?? 'ride').toString();
    final title = (data['title'] ?? 'Commute Post').toString();
    final timeStr = data['time_str']?.toString();
    final minutesRemaining = (data['minutes_remaining'] as num?)?.toInt() ?? 30;

    NotificationSoundService.playMessageChime();
    SystemNotificationService.showNotification(
      title: '⚠️ Scheduled Ride Time Reached: Extend Time',
      body: 'Your post ($title) reached its departure time. Please extend within 30 mins or it will be deleted.',
      id: 'ext_$postId',
    );

    PostExpiryExtensionDialog.show(
      context,
      postId: postId,
      postType: postType,
      title: title,
      scheduledTimeStr: timeStr,
      initialMinutesRemaining: minutesRemaining,
    );
  }

  void _handlePostExpiredAndDeleted(Map<String, dynamic> data) {
    ref.invalidate(allAvailableRidesProvider);
    ref.invalidate(departingSoonRidesProvider);
    ref.invalidate(passengerRequestsProvider);

    if (!mounted) return;
    final currentAuth = ref.read(authNotifierProvider).user;
    if (currentAuth == null) return;

    final targetUserId = (data['userId'] ?? '').toString().trim();
    final isOwner = targetUserId.isNotEmpty && (
      targetUserId == currentAuth.id ||
      targetUserId == currentAuth.studentId ||
      (currentAuth.phone.isNotEmpty && targetUserId == currentAuth.phone)
    );

    if (isOwner) {
      final title = (data['title'] ?? 'Post').toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ Scheduled post "$title" expired after 30 mins and was automatically removed.'),
          backgroundColor: const Color(0xFFDC2626),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _handleUniversityNotice(Map<String, dynamic> data) {
    if (!mounted) return;
    final title = data['title']?.toString() ?? 'Official Varsity Notice';
    final message = data['message']?.toString() ??
        data['content']?.toString() ??
        data['body']?.toString() ??
        '';
    final audience = data['audience']?.toString() ??
        data['targetAudience']?.toString() ??
        'all';
    final noticeId = data['id']?.toString() ?? 'notc_${DateTime.now().millisecondsSinceEpoch}';

    // ignore: avoid_print
    print('[DIU_NOTIFICATION] Varsity Authority Notice received: $title | $message | Audience: $audience');
    NotificationSoundService.playMessageChime();

    try {
      ref.read(notificationsProvider.notifier).onUniversityNotice(
        title: title,
        message: message,
        audience: audience,
        id: noticeId,
      );
    } catch (_) {}

    // Invoke native Android Status Bar Notification
    SystemNotificationService.showNotification(
      title: '📢 DIU Notice: $title',
      body: message,
      id: noticeId,
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFFFFF3E0),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.campaign, color: Color(0xFFE65100), size: 28),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Varsity Authority Notice',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFE65100),
                    ),
                  ),
                  Text(
                    'Daffodil International University',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF1C1C1E)),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Text(
                message,
                style: const TextStyle(fontSize: 13, color: Color(0xFF374151), height: 1.45),
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE65100),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Acknowledge'),
          ),
        ],
      ),
    );
  }

  BuildContext? _activeRingDialogContext;

  void _handleRemoteStopRing(Map<String, dynamic> msg) {
    NotificationSoundService.stopRinging();
    if (_activeRingDialogContext != null && mounted) {
      try {
        Navigator.of(_activeRingDialogContext!).pop();
      } catch (_) {}
      _activeRingDialogContext = null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ringing was cancelled by caller.'),
          backgroundColor: Color(0xFFD84315),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _showAlertRingBuzzer(Map<String, dynamic> msg) {
    if (!mounted) return;

    final targetUserId = (msg['targetUserId'] ?? '').toString().trim();
    final targetName = (msg['targetName'] ?? '').toString().trim();
    final senderId = (msg['senderId'] ?? '').toString().trim();
    final sender = (msg['senderName'] ?? 'Campus Peer').toString();
    final alertMsg = msg['message'] ?? '🚨 Urgent: Attention requested for pickup!';
    final rideId = msg['rideId']?.toString() ?? 'general';
    final ringId = (msg['ringId'] ?? msg['id'] ?? '').toString();

    final currentAuth = ref.read(authNotifierProvider).user;
    if (currentAuth == null) return;

    // Check if current user is the sender (NEVER ring the caller themselves!)
    final isSender = senderId.isNotEmpty && (
        senderId == currentAuth.id ||
        senderId == currentAuth.studentId ||
        (currentAuth.phone.isNotEmpty && senderId == currentAuth.phone) ||
        (currentAuth.email.isNotEmpty && senderId.toLowerCase() == currentAuth.email.toLowerCase()) ||
        (sender.isNotEmpty && sender.toLowerCase() == currentAuth.name.toLowerCase())
    );
    if (isSender) return; // Do not ring yourself

    // Dedicated ring check: only ring if this user is explicitly targeted
    final isTarget = targetUserId.isNotEmpty && (
        targetUserId == currentAuth.id ||
        targetUserId == currentAuth.studentId ||
        (currentAuth.phone.isNotEmpty && targetUserId == currentAuth.phone) ||
        (currentAuth.email.isNotEmpty && targetUserId.toLowerCase() == currentAuth.email.toLowerCase()) ||
        (targetName.isNotEmpty && targetName.toLowerCase() == currentAuth.name.toLowerCase()) ||
        targetUserId.toLowerCase() == currentAuth.name.toLowerCase()
    );

    if (!isTarget) return; // Dedicated! Ignore rings targeted at other students

    // Play loud dedicated ringing buzzer sound + continuous vibration
    NotificationSoundService.playRingAlert(durationSeconds: 25);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        _activeRingDialogContext = ctx;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: Colors.white,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFEBE6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.notifications_active, color: Color(0xFFD84315), size: 28),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Incoming Ring Alert!',
                  style: TextStyle(color: Color(0xFFD84315), fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$sender is ringing you!',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Text(
                  alertMsg,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFD32F2F),
                      side: const BorderSide(color: Color(0xFFD32F2F)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.call_end, size: 18),
                    label: const Text('Stop Ringing', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () {
                      NotificationSoundService.stopRinging();
                      _activeRingDialogContext = null;
                      Navigator.pop(ctx);
                      try {
                        ref.read(ridesRepositoryProvider).stopAlertRing(
                          targetUserId: targetUserId,
                          senderId: senderId,
                          ringId: ringId,
                        );
                      } catch (_) {}
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.chat, size: 18),
                    label: const Text('Answer Chat', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () {
                      NotificationSoundService.stopRinging();
                      _activeRingDialogContext = null;
                      Navigator.pop(ctx);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            rideId: rideId,
                            peerName: sender,
                            driverName: sender,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        );
      },
    ).then((_) {
      _activeRingDialogContext = null;
      NotificationSoundService.stopRinging();
    });
  }

  void _handleIncomingChatMessage(Map<String, dynamic> msg) {
    if (!mounted) return;
    final currentUserId = ref.read(authNotifierProvider).user?.id ?? '';
    final senderId = msg['senderId']?.toString() ?? '';

    // Ignore messages sent by self
    if (senderId.isNotEmpty && senderId == currentUserId) return;

    // Play crisp notification chime
    NotificationSoundService.playMessageChime();

    setState(() {
      _unreadChatCount++;
    });

    final senderName = msg['senderName'] ?? 'Campus Peer';
    final text = msg['text'] ?? 'Sent a message';
    final rideId = msg['rideId']?.toString() ?? 'general';

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: Color(0xFFE65100),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.chat_bubble, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    senderName,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  Text(
                    text,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'Reply',
          textColor: const Color(0xFFFFA000),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatScreen(
                  rideId: rideId,
                  peerName: senderName,
                  driverName: senderName,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _handleRideBookingRequest(Map<String, dynamic> data) {
    if (!mounted) return;
    final currentAuth = ref.read(authNotifierProvider).user;
    if (currentAuth == null) return;

    final driverId = (data['driverId'] ?? '').toString().trim();
    final driverName = (data['driverName'] ?? '').toString().trim();

    final isDriver = driverId.isNotEmpty && (
        driverId == currentAuth.id ||
        driverId == currentAuth.studentId ||
        (currentAuth.phone.isNotEmpty && driverId == currentAuth.phone) ||
        (driverName.isNotEmpty && driverName.toLowerCase() == currentAuth.name.toLowerCase())
    );

    if (!isDriver) return;

    NotificationSoundService.playMessageChime();
    ref.invalidate(allAvailableRidesProvider);
    ref.invalidate(myBookingsProvider);

    final passengerName = data['passengerName'] ?? 'Student';
    final pickup = data['pickup'] ?? 'Campus';
    final dropoff = data['dropoff'] ?? 'Destination';
    final rideId = data['rideId']?.toString() ?? 'general';

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: const BoxDecoration(
                color: Color(0xFF2E7D32),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_add_alt_1, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🔔 New Seat Booking Request!',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  Text(
                    '$passengerName: $pickup ➔ $dropoff',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'Open Chat',
          textColor: const Color(0xFF4CAF50),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatScreen(
                  rideId: rideId,
                  peerName: passengerName,
                  driverName: currentAuth.name,
                  peerRole: 'Passenger',
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _handleRideBookingAccepted(Map<String, dynamic> data) {
    if (!mounted) return;
    final currentAuth = ref.read(authNotifierProvider).user;
    if (currentAuth == null) return;

    final passengerId = (data['passengerId'] ?? '').toString().trim();
    final passengerName = (data['passengerName'] ?? '').toString().trim();

    final isPassenger = passengerId.isNotEmpty && (
        passengerId == currentAuth.id ||
        passengerId == currentAuth.studentId ||
        (currentAuth.phone.isNotEmpty && passengerId == currentAuth.phone) ||
        (passengerName.isNotEmpty && passengerName.toLowerCase() == currentAuth.name.toLowerCase())
    );

    if (!isPassenger) return;

    NotificationSoundService.playMessageChime();
    ref.invalidate(myBookingsProvider);
    ref.invalidate(allAvailableRidesProvider);

    final driverName = data['driverName'] ?? 'Rider';
    final rideId = data['rideId']?.toString() ?? 'general';

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: const BoxDecoration(
                color: Color(0xFF10B981),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '✅ Ride Confirmed by Rider!',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  Text(
                    '$driverName accepted your seat request.',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'Chat',
          textColor: const Color(0xFF10B981),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatScreen(
                  rideId: rideId,
                  peerName: driverName,
                  driverName: driverName,
                  peerRole: 'Rider',
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _handleRideSessionStatusChanged(Map<String, dynamic> data) {
    if (!mounted) return;
    ref.invalidate(allAvailableRidesProvider);
    ref.invalidate(myBookingsProvider);

    final status = data['status']?.toString();

    if (status == 'in_progress') {
      NotificationSoundService.playMessageChime();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🚀 Both confirmed! Ride is now in progress • Timer started.'),
          backgroundColor: Color(0xFF047857),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
    } else if (status == 'completed') {
      NotificationSoundService.playMessageChime();
      final mins = data['totalDurationMinutes'] ?? '15';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🏁 Trip Completed! Total time: $mins min(s). Have a great day!'),
          backgroundColor: const Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } else if (status == 'cancelled') {
      final reason = data['cancelReason'] ?? 'Cancelled by user';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Ride was cancelled: $reason'),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _onTabSelected(int index) {
    setState(() {
      _currentTab = index;
      if (index == 3) {
        _unreadChatCount = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Screens that render their own AppBar (no DiuAppHeader needed)
    final noHeaderTabs = {0, 1, 3, 4}; // Home, All Rides, Messages, and Profile have their own headers

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: noHeaderTabs.contains(_currentTab)
          ? null
          : DiuAppHeader(
              title: _titles[_currentTab],
              onProfileTap: () => _onTabSelected(4),
              onNotificationsTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                );
              },
            ),
      body: Column(
        children: [
          _buildVarsityNoticeNotificationBar(),
          Expanded(
            child: IndexedStack(
              index: _currentTab,
              children: [
                // 0. Home Screen
                HomeScreen(
                  onNavigateTab: _onTabSelected,
                  onSearchQuery: (query) {
                    ref.read(rideSearchFilterProvider.notifier).setDropoff(query);
                  },
                ),

                // 1. All Shared Rides Screen
                const AllSharedRidesScreen(),

                // 2. Offer / Create Ride Screen
                OfferRideScreen(
                  onRidePublished: () {
                    _onTabSelected(1); // Jump to All Rides after publishing
                  },
                ),

                // 3. Campus SMS & Direct Messages
                CampusMessagesScreen(
                  onExploreRides: () => _onTabSelected(1),
                ),

                // 4. Student Profile
                const ProfileScreen(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: DiuBottomNav(
        currentIndex: _currentTab,
        onTap: _onTabSelected,
        unreadChats: _unreadChatCount,
      ),
    );
  }

  Widget _buildVarsityNoticeNotificationBar() {
    final notifications = ref.watch(notificationsProvider);
    // Find newest unread varsity notice
    final unreadNotice = notifications.cast<NotificationModel?>().firstWhere(
      (n) => n != null && !n.isRead && n.type == NotificationType.safetyAlert && n.title.contains('📢'),
      orElse: () => null,
    );

    if (unreadNotice == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE65100), Color(0xFFF57C00)],
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.campaign, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: () {
                _showNoticeDetailsDialog(unreadNotice);
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    unreadNotice.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    unreadNotice.body,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Dismiss notice banner',
            onPressed: () {
              ref.read(notificationsProvider.notifier).markAsRead(unreadNotice.id);
            },
          ),
        ],
      ),
    );
  }

  void _showNoticeDetailsDialog(NotificationModel notice) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFFFFF3E0),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.campaign, color: Color(0xFFE65100), size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notice.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFE65100),
                    ),
                  ),
                  const Text(
                    'Daffodil International University',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Text(
          notice.body,
          style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () {
              ref.read(notificationsProvider.notifier).markAsRead(notice.id);
              Navigator.pop(ctx);
            },
            child: const Text('Dismiss', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE65100),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              ref.read(notificationsProvider.notifier).markAsRead(notice.id);
              Navigator.pop(ctx);
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              );
            },
            child: const Text('View All Notices'),
          ),
        ],
      ),
    );
  }
}
