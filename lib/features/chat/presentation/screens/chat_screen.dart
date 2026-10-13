import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/config/app_config.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/network/websocket_client.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/core/utils/date_time_utils.dart';
import 'package:diu_ride/core/utils/gps_location_service.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/chat/presentation/providers/chat_provider.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';
import 'package:diu_ride/features/safety/presentation/widgets/campus_voice_call_dialog.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:diu_ride/core/services/notification_sound_service.dart';
import 'package:diu_ride/features/chat/data/models/chat_message.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String rideId;
  final String driverName;
  final String? peerName;
  final String vehicleModel;
  final String? peerPhone;
  final String? peerRole;

  const ChatScreen({
    super.key,
    required this.rideId,
    this.driverName = 'Ride Companion',
    this.peerName,
    this.vehicleModel = 'Campus Ride',
    this.peerPhone,
    this.peerRole,
  });

  String get displayName => peerName ?? driverName;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  StreamSubscription? _wsSessionSub;
  Timer? _rideProgressTimer;
  int _rideElapsedSeconds = 0;
  bool _isLoadingSession = false;

  // Session state variables
  String _sessionStatus = 'pending'; // 'pending', 'in_progress', 'completed', 'cancelled'
  bool _riderConfirmed = false;
  bool _passengerConfirmed = false;
  DateTime? _rideStartTime;
  String _cancelReason = '';
  double _rideFare = 60.0;
  String _originName = 'DIU Campus';
  String _destinationName = 'Destination';
  double _totalDurationMinutes = 0.0;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      _loadSessionStatus();
      _listenWebSocketSession();
    });
  }

  Future<void> _triggerAlertRing() async {
    final user = ref.read(authNotifierProvider).user;
    final senderName = user?.name ?? 'Commuter';
    final ringId = 'ring_${DateTime.now().millisecondsSinceEpoch}';
    final targetId = widget.peerPhone?.isNotEmpty == true
        ? widget.peerPhone!
        : (widget.peerName?.isNotEmpty == true ? widget.peerName! : widget.driverName);

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              backgroundColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9500).withOpacity(0.15),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF9500).withOpacity(0.3),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.notifications_active, color: Color(0xFFFF9500), size: 38),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Ringing ${widget.displayName}...',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Dedicated alert buzzer is ringing on their phone. Tap Stop to cancel at any time.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.grey[700], height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD32F2F),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.call_end, size: 20),
                      label: const Text('Stop Ringing', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      onPressed: () async {
                        NotificationSoundService.stopRinging();
                        try {
                          await ref.read(ridesRepositoryProvider).stopAlertRing(
                            targetUserId: targetId,
                            senderId: user?.id,
                            ringId: ringId,
                          );
                        } catch (_) {}
                        if (context.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Ringing stopped.'),
                              backgroundColor: Color(0xFFD32F2F),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }

    try {
      await ref.read(ridesRepositoryProvider).triggerAlertRing(
        targetUserId: targetId,
        targetName: widget.displayName,
        senderId: user?.id ?? '',
        senderName: senderName,
        rideId: widget.rideId,
        ringId: ringId,
        message: '🚨 Urgent: $senderName is ringing you for pickup!',
      );
    } catch (_) {}

    ref.read(chatNotifierProvider(widget.rideId).notifier).sendMessage(
      '🚨 [Alert Ring] Dedicated attention buzz sent to ${widget.displayName}',
    );
    _scrollToBottom();
  }

  @override
  void dispose() {
    _rideProgressTimer?.cancel();
    _wsSessionSub?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String get _apiBase {
    if (kIsWeb) {
      final origin = Uri.base.origin;
      return '$origin/ride/api';
    }
    return AppConfig.current.apiBaseUrl;
  }

  Future<void> _loadSessionStatus() async {
    if (widget.rideId == 'campus_community' || widget.rideId == 'support_campus') return;
    try {
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 4)));
      final res = await dio.get('$_apiBase/rides/${widget.rideId}/session-status');
      if (res.statusCode == 200 && res.data is Map) {
        final d = Map<String, dynamic>.from(res.data as Map);
        if (mounted) {
          setState(() {
            _sessionStatus = d['status']?.toString() ?? 'pending';
            _riderConfirmed = d['riderConfirmed'] == true;
            _passengerConfirmed = d['passengerConfirmed'] == true;
            _originName = d['origin']?.toString() ?? _originName;
            _destinationName = d['destination']?.toString() ?? _destinationName;
            _rideFare = (d['fare'] as num?)?.toDouble() ?? _rideFare;
            _cancelReason = d['cancelReason']?.toString() ?? '';
            _totalDurationMinutes = (d['totalDurationMinutes'] as num?)?.toDouble() ?? 0.0;
            if (d['startTime'] != null) {
              _rideStartTime = DateTime.tryParse(d['startTime'].toString());
            }
          });
          if (_sessionStatus == 'in_progress') {
            _startProgressTimer();
          }
        }
      }
    } catch (_) {}
  }

  void _listenWebSocketSession() {
    final wsClient = ref.read(webSocketClientProvider);
    _wsSessionSub?.cancel();
    _wsSessionSub = wsClient.messages.listen((msg) {
      final event = msg['event'] ?? msg['type'];
      final data = msg['data'] is Map ? Map<String, dynamic>.from(msg['data'] as Map) : msg;
      if (event == 'ride_session_status_changed' && data['rideId'] == widget.rideId) {
        if (!mounted) return;
        setState(() {
          _sessionStatus = data['status']?.toString() ?? _sessionStatus;
          if (data.containsKey('riderConfirmed')) {
            _riderConfirmed = data['riderConfirmed'] == true;
          }
          if (data.containsKey('passengerConfirmed')) {
            _passengerConfirmed = data['passengerConfirmed'] == true;
          }
          if (data.containsKey('cancelReason')) {
            _cancelReason = data['cancelReason']?.toString() ?? '';
          }
          if (data.containsKey('totalDurationMinutes')) {
            _totalDurationMinutes = (data['totalDurationMinutes'] as num?)?.toDouble() ?? _totalDurationMinutes;
          }
          if (data['startTime'] != null) {
            _rideStartTime = DateTime.tryParse(data['startTime'].toString());
          }
        });

        if (_sessionStatus == 'in_progress') {
          _startProgressTimer();
        } else {
          _rideProgressTimer?.cancel();
        }

        ref.read(chatNotifierProvider(widget.rideId).notifier).loadMessages();
        _scrollToBottom();
      }
    });
  }

  void _startProgressTimer() {
    _rideProgressTimer?.cancel();
    if (_rideStartTime != null) {
      _rideElapsedSeconds = DateTime.now().difference(_rideStartTime!).inSeconds;
      if (_rideElapsedSeconds < 0) _rideElapsedSeconds = 0;
    }
    _rideProgressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _rideElapsedSeconds++;
      });
    });
  }

  Future<void> _confirmRideSession() async {
    final user = ref.read(authNotifierProvider).user;
    final role = (widget.peerRole?.toLowerCase() == 'passenger') ? 'rider' : 'passenger';
    setState(() => _isLoadingSession = true);
    try {
      final pos = await GpsLocationService.getCurrentLocation();
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 5)));
      await dio.post('$_apiBase/rides/confirm-session', data: {
        'rideId': widget.rideId,
        'userId': user?.id ?? '',
        'userName': user?.name ?? 'Student',
        'role': role,
        'latitude': pos?.latitude ?? 23.8765,
        'longitude': pos?.longitude ?? 90.3204,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ You confirmed this ride!'),
          backgroundColor: Color(0xFF10B981),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Confirmation failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoadingSession = false);
    }
  }

  Future<void> _startRideSession() async {
    final user = ref.read(authNotifierProvider).user;
    setState(() => _isLoadingSession = true);
    try {
      final pos = await GpsLocationService.getCurrentLocation();
      final lat = pos?.latitude ?? 23.8765;
      final lng = pos?.longitude ?? 90.3204;
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 5)));
      await dio.post('$_apiBase/rides/${widget.rideId}/start', data: {
        'latitude': lat,
        'longitude': lng,
      });

      ref.read(chatNotifierProvider(widget.rideId).notifier).sendMessage(
        '🚀 [Trip Started] ${user?.name ?? "Rider"} started the ride! Live GPS tracking is active.',
      );

      if (mounted) {
        setState(() {
          _sessionStatus = 'in_progress';
          _rideStartTime = DateTime.now();
        });
        _startProgressTimer();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🚀 Trip started! Live timer and GPS active.'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start trip: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingSession = false);
    }
  }

  void _showCancelTripDialog() {
    final reasons = [
      'Fare not agreed / ভাড়া বনিবনা হয়নি',
      'Peer not responding / মেসেজ বা কলে উত্তর নেই',
      'Change of travel plans / ভ্রমণ পরিকল্পনা পরিবর্তন',
      'Vehicle or location mismatch / স্থান বা বাহন মিলছে না',
      'Other / অন্যান্য',
    ];
    String selected = reasons[0];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.cancel_outlined, color: Color(0xFFEF4444), size: 24),
                  SizedBox(width: 8),
                  Text(
                    'Cancel / Close Trip',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'If contact or fare is not agreed, cancel this trip now. Both parties will be notified and the ride will not be confirmed.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ...reasons.map((r) => RadioListTile<String>(
                title: Text(r, style: const TextStyle(fontSize: 13.5)),
                value: r,
                groupValue: selected,
                contentPadding: EdgeInsets.zero,
                activeColor: const Color(0xFFEF4444),
                onChanged: (val) {
                  if (val != null) setModalState(() => selected = val);
                },
              )),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _cancelRideSession(selected);
                  },
                  child: const Text('Confirm Cancel Trip', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _cancelRideSession(String reason) async {
    final user = ref.read(authNotifierProvider).user;
    final role = (widget.peerRole?.toLowerCase() == 'passenger') ? 'rider' : 'passenger';
    setState(() => _isLoadingSession = true);
    try {
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 5)));
      await dio.post('$_apiBase/rides/cancel-session', data: {
        'rideId': widget.rideId,
        'userId': user?.id ?? '',
        'userName': user?.name ?? 'Student',
        'role': role,
        'reason': reason,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Trip cancelled: $reason'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cancel failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoadingSession = false);
    }
  }

  Future<void> _completeRideSession() async {
    final user = ref.read(authNotifierProvider).user;
    final role = (widget.peerRole?.toLowerCase() == 'passenger') ? 'rider' : 'passenger';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.flag, color: Color(0xFF10B981)),
            SizedBox(width: 8),
            Text('Complete Trip?'),
          ],
        ),
        content: const Text(
          'Have you arrived safely at your destination? Marking this trip complete will record the arrival time, calculate total duration, and save the ride record to the database.',
          style: TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not Yet')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Arrived & Complete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoadingSession = true);
    try {
      final pos = await GpsLocationService.getCurrentLocation();
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 5)));
      await dio.post('$_apiBase/rides/complete-session', data: {
        'rideId': widget.rideId,
        'userId': user?.id ?? '',
        'userName': user?.name ?? 'Student',
        'role': role,
        'latitude': pos?.latitude ?? 23.8765,
        'longitude': pos?.longitude ?? 90.3204,
      });
      if (!mounted) return;
      setState(() {
        _sessionStatus = 'completed';
      });
      ref.read(chatNotifierProvider(widget.rideId).notifier).loadMessages();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🏁 Trip marked as completed! Record saved to database.'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Completion failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoadingSession = false);
    }
  }

  Widget _buildRideSessionControlBar() {
    if (widget.rideId == 'campus_community' || widget.rideId == 'support_campus') {
      return const SizedBox();
    }

    final isRider = (widget.peerRole?.toLowerCase() == 'passenger');
    final myConfirmed = isRider ? _riderConfirmed : _passengerConfirmed;
    final peerConfirmed = isRider ? _passengerConfirmed : _riderConfirmed;
    final peerLabel = isRider ? 'Passenger' : 'Rider';

    final minutes = (_rideElapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_rideElapsedSeconds % 60).toString().padLeft(2, '0');

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _sessionStatus == 'in_progress'
              ? const Color(0xFF10B981)
              : (_sessionStatus == 'completed'
                  ? const Color(0xFF059669)
                  : (_sessionStatus == 'cancelled'
                      ? const Color(0xFFEF4444).withOpacity(0.5)
                      : AppColors.outline.withOpacity(0.2))),
          width: 1.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _sessionStatus == 'in_progress'
                  ? const Color(0xFF10B981).withOpacity(0.12)
                  : (_sessionStatus == 'completed'
                      ? const Color(0xFF059669).withOpacity(0.1)
                      : (_sessionStatus == 'cancelled'
                          ? const Color(0xFFEF4444).withOpacity(0.1)
                          : AppColors.surfaceContainerHigh.withOpacity(0.3))),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Icon(
                  _sessionStatus == 'in_progress'
                      ? Icons.directions_bike
                      : (_sessionStatus == 'completed'
                          ? Icons.check_circle
                          : (_sessionStatus == 'cancelled'
                              ? Icons.cancel
                              : Icons.hourglass_top)),
                  size: 16,
                  color: _sessionStatus == 'in_progress'
                      ? const Color(0xFF10B981)
                      : (_sessionStatus == 'completed'
                          ? const Color(0xFF059669)
                          : (_sessionStatus == 'cancelled' ? const Color(0xFFEF4444) : AppColors.primary)),
                ),
                const SizedBox(width: 8),
                Text(
                  _sessionStatus == 'in_progress'
                      ? 'RIDE IN PROGRESS • READY TO RIDE'
                      : (_sessionStatus == 'completed'
                          ? 'TRIP COMPLETED'
                          : (_sessionStatus == 'cancelled'
                              ? 'TRIP CANCELLED (Not Confirmed)'
                              : 'RIDE CONFIRMATION REQUIRED')),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: _sessionStatus == 'in_progress'
                        ? const Color(0xFF047857)
                        : (_sessionStatus == 'completed'
                            ? const Color(0xFF065F46)
                            : (_sessionStatus == 'cancelled' ? const Color(0xFFDC2626) : AppColors.primary)),
                  ),
                ),
                const Spacer(),
                if (_sessionStatus == 'in_progress')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer, size: 12, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          '$minutes:$seconds',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Text(
                    '৳${_rideFare.toStringAsFixed(0)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primary),
                  ),
              ],
            ),
          ),

          // Body Details
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Route info
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$_originName ➔ $_destinationName',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // STATE 1: PENDING CONFIRMATION
                if (_sessionStatus == 'pending') ...[
                  Row(
                    children: [
                      // My status pill
                      _buildStatusPill(
                        label: 'You: ${myConfirmed ? "Confirmed ✓" : "Pending"}',
                        isConfirmed: myConfirmed,
                      ),
                      const SizedBox(width: 8),
                      // Peer status pill
                      _buildStatusPill(
                        label: '$peerLabel: ${peerConfirmed ? "Confirmed ✓" : "Pending"}',
                        isConfirmed: peerConfirmed,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      // Confirm button
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: myConfirmed ? const Color(0xFF047857) : const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: (_isLoadingSession || myConfirmed) ? null : _confirmRideSession,
                          icon: Icon(myConfirmed ? Icons.check : Icons.check_circle_outline, size: 15),
                          label: Text(
                            myConfirmed ? 'Confirmed ✓' : 'Confirm Order',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Start Trip directly
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE65100),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _isLoadingSession ? null : _startRideSession,
                          icon: const Icon(Icons.play_arrow, size: 15),
                          label: const Text(
                            'Start Trip',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Close / Cancel Trip button
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFEF4444),
                          side: const BorderSide(color: Color(0xFFEF4444)),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _isLoadingSession ? null : _showCancelTripDialog,
                        icon: const Icon(Icons.close, size: 14),
                        label: const Text(
                          'Cancel',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],

                // STATE 2: IN PROGRESS (BOTH CONFIRMED)
                if (_sessionStatus == 'in_progress') ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _shareLocation,
                          icon: const Icon(Icons.my_location, size: 15),
                          label: const Text('Share Live GPS', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF047857),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _isLoadingSession ? null : _completeRideSession,
                          icon: const Icon(Icons.flag, size: 15),
                          label: const Text('End Trip (Complete)', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFEF4444),
                          side: const BorderSide(color: Color(0xFFEF4444)),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _isLoadingSession ? null : _showCancelTripDialog,
                        icon: const Icon(Icons.close, size: 14),
                        label: const Text('Cancel', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],

                // STATE 3: COMPLETED
                if (_sessionStatus == 'completed') ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF10B981)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.check_circle, color: Color(0xFF047857), size: 18),
                            const SizedBox(width: 6),
                            const Text(
                              '✓ PREVIOUS RIDE COMPLETED',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF065F46),
                                letterSpacing: 0.3,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD1FAE5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '৳${_rideFare.toStringAsFixed(0)}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF047857)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Route: $_originName ➔ $_destinationName\nDuration: ${_totalDurationMinutes > 0 ? _totalDurationMinutes.toStringAsFixed(1) : "15"} mins • Safe arrival archived in database.',
                          style: const TextStyle(fontSize: 11.5, color: Color(0xFF047857), height: 1.35),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.two_wheeler, size: 14, color: AppColors.primary),
                      label: const Text('Find / Post Next Ride ➔', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
                    ),
                  ),
                ],

                // STATE 4: CANCELLED
                if (_sessionStatus == 'cancelled') ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _cancelReason.isNotEmpty ? 'Reason: $_cancelReason' : 'Trip cancelled before confirmation.',
                          style: const TextStyle(fontSize: 11.5, color: Color(0xFFDC2626)),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Find Another ➔', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPill({required String label, required bool isConfirmed}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isConfirmed ? const Color(0xFFD1FAE5) : const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isConfirmed ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isConfirmed ? Icons.check_circle : Icons.schedule,
            size: 12,
            color: isConfirmed ? const Color(0xFF047857) : const Color(0xFFB45309),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              color: isConfirmed ? const Color(0xFF047857) : const Color(0xFFB45309),
            ),
          ),
        ],
      ),
    );
  }

  void _sendMessage() {
    final text = _messageController.text;
    if (text.trim().isEmpty) return;
    ref.read(chatNotifierProvider(widget.rideId).notifier).sendMessage(text);
    _messageController.clear();
    _scrollToBottom();
  }

  Future<void> _shareLocation() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Acquiring device GPS coordinates...'),
        duration: Duration(seconds: 1),
      ),
    );
    final pos = await GpsLocationService.getCurrentLocation();
    final lat = pos?.latitude ?? 23.8765;
    final lng = pos?.longitude ?? 90.3204;
    if (!mounted) return;
    ref.read(chatNotifierProvider(widget.rideId).notifier).shareLocation(lat, lng);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatNotifierProvider(widget.rideId));
    final displayName = widget.displayName;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceContainerLowest,
        elevation: 0.5,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primaryContainer,
              child: Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : 'C',
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(displayName, style: AppTypography.bodyLgMedium),
                    const SizedBox(width: 4),
                    const Icon(Icons.verified, size: 14, color: AppColors.primary),
                  ],
                ),
                Text(
                  '${widget.peerRole ?? widget.vehicleModel} • Live Chat',
                  style: AppTypography.labelSm.copyWith(color: AppColors.primary, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_active, color: Color(0xFFFF9500)),
            tooltip: 'Alert Ring (রিং বাজান)',
            onPressed: _triggerAlertRing,
          ),
          IconButton(
            icon: const Icon(Icons.call, color: AppColors.primary),
            tooltip: 'Campus Voice Call',
            onPressed: () {
              CampusVoiceCallDialog.show(
                context,
                peerName: displayName,
                peerPhone: widget.peerPhone ?? '01712345678',
                peerRole: widget.peerRole ?? 'Ride Companion',
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildRideSessionControlBar(),
          // Messages list
          Expanded(
            child: chatState.isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: chatState.messages.length,
                    itemBuilder: (context, index) {
                      final msg = chatState.messages[index];
                      if (_isTripCompletedMessage(msg)) {
                        return _buildTripCompletedBox(msg);
                      }
                      return Align(
                        alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.78,
                          ),
                          decoration: BoxDecoration(
                            color: msg.isMe ? AppColors.primary : AppColors.surfaceContainerLowest,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: Radius.circular(msg.isMe ? 16 : 4),
                              bottomRight: Radius.circular(msg.isMe ? 4 : 16),
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: AppColors.cardShadow,
                                blurRadius: 4,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment:
                                msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              if (msg.isLocationShare || msg.text.contains('google.com/maps') || msg.text.contains('maps.google.com') || msg.sharedLat != null) ...[
                                _buildLocationCard(msg),
                              ],
                              if (!msg.isMe && msg.senderName.isNotEmpty) ...[
                                Text(
                                  msg.senderName,
                                  style: AppTypography.labelSm.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                              ],
                              _buildClickableMessageText(msg),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    DateTimeUtils.formatTime(msg.timestamp),
                                    style: AppTypography.labelSm.copyWith(
                                      color: msg.isMe
                                          ? AppColors.onPrimary.withOpacity(0.7)
                                          : AppColors.outline,
                                      fontSize: 10,
                                    ),
                                  ),
                                  if (msg.isMe) ...[
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.done_all,
                                      size: 13,
                                      color: AppColors.primaryFixed,
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Message input bar
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.cardShadow,
                    blurRadius: 8,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.my_location, color: AppColors.secondary),
                    tooltip: 'Share Campus Location',
                    onPressed: _shareLocation,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: AppTypography.bodyMd.copyWith(color: AppColors.outline),
                        filled: true,
                        fillColor: AppColors.surfaceContainerLow,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: AppColors.primary,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: AppColors.onPrimary, size: 18),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isTripCompletedMessage(ChatMessage msg) {
    final lower = msg.text.toLowerCase();
    return lower.contains('trip completed') ||
           lower.contains('trip successfully completed') ||
           lower.contains('ride completed') ||
           lower.contains('[trip completed]');
  }

  Widget _buildTripCompletedBox(ChatMessage msg) {
    final timeStr = DateTimeUtils.formatTime(msg.timestamp);
    final text = msg.text
        .replaceAll('🏁', '')
        .replaceAll('[Trip Completed]', '')
        .trim();

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        padding: const EdgeInsets.all(14),
        constraints: const BoxConstraints(maxWidth: 440),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF86EFAC), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF16A34A).withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Color(0xFF16A34A),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 14),
                ),
                const SizedBox(width: 8),
                const Text(
                  'TRIP COMPLETED',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    color: Color(0xFF15803D),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.access_time, size: 11, color: Color(0xFF16A34A)),
                      const SizedBox(width: 3),
                      Text(
                        timeStr,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF15803D),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
                      height: 1.45,
                    ),
                  ),
                  if (msg.sharedLat != null && msg.sharedLng != null) ...[
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () {
                        final url = GpsLocationService.getGoogleMapsLocationUrl(msg.sharedLat!, msg.sharedLng!);
                        GpsLocationService.openGoogleMaps(url);
                      },
                      child: const Row(
                        children: [
                          Icon(Icons.location_on, size: 14, color: Color(0xFF16A34A)),
                          SizedBox(width: 4),
                          Text(
                            'Open Destination in Google Maps',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF15803D),
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationCard(ChatMessage msg) {
    double lat = msg.sharedLat ?? 23.8765;
    double lng = msg.sharedLng ?? 90.3204;
    if (msg.sharedLat == null || msg.sharedLng == null) {
      final match = RegExp(r'query=(-?\d+\.\d+),(-?\d+\.\d+)').firstMatch(msg.text) ??
          RegExp(r'(-?\d{1,2}\.\d{3,})\s*,\s*(-?\d{1,3}\.\d{3,})').firstMatch(msg.text);
      if (match != null) {
        lat = double.tryParse(match.group(1)!) ?? lat;
        lng = double.tryParse(match.group(2)!) ?? lng;
      }
    }

    final mapsUrl = GpsLocationService.getGoogleMapsLocationUrl(lat, lng);
    final directionsUrl = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving';

    return InkWell(
      onTap: () => GpsLocationService.openGoogleMaps(mapsUrl),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: msg.isMe ? Colors.white.withOpacity(0.22) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: msg.isMe ? Colors.white30 : const Color(0xFFCBD5E1),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: msg.isMe ? Colors.white : AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.location_on,
                    size: 16,
                    color: msg.isMe ? AppColors.primary : Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Live GPS Location Shared',
                        style: TextStyle(
                          color: msg.isMe ? Colors.white : const Color(0xFF0F172A),
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                        ),
                      ),
                      Text(
                        '${lat.toStringAsFixed(5)}° N, ${lng.toStringAsFixed(5)}° E',
                        style: TextStyle(
                          color: msg.isMe ? Colors.white70 : const Color(0xFF64748B),
                          fontSize: 10.5,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => GpsLocationService.openGoogleMaps(mapsUrl),
                    icon: const Icon(Icons.map, size: 14),
                    label: const Text('Open in Google Maps', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: msg.isMe ? Colors.white : AppColors.primary,
                      foregroundColor: msg.isMe ? AppColors.primary : Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => GpsLocationService.openGoogleMaps(directionsUrl),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: msg.isMe ? Colors.white24 : Colors.white,
                      border: Border.all(color: msg.isMe ? Colors.white30 : const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.directions, size: 14, color: msg.isMe ? Colors.white : AppColors.primary),
                        const SizedBox(width: 4),
                        Text(
                          'Route',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: msg.isMe ? Colors.white : AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClickableMessageText(ChatMessage msg) {
    final text = msg.text;
    final urlRegex = RegExp(r'(https?:\/\/[^\s]+)');
    final matches = urlRegex.allMatches(text);

    if (matches.isEmpty) {
      return Text(
        text,
        style: AppTypography.bodyMd.copyWith(
          color: msg.isMe ? AppColors.onPrimary : AppColors.onSurface,
        ),
      );
    }

    final spans = <InlineSpan>[];
    int lastIndex = 0;

    for (final match in matches) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: text.substring(lastIndex, match.start),
          style: TextStyle(color: msg.isMe ? AppColors.onPrimary : AppColors.onSurface),
        ));
      }
      final url = match.group(0)!;
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: InkWell(
          onTap: () async {
            final uri = Uri.parse(url);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          child: Text(
            url,
            style: TextStyle(
              color: msg.isMe ? const Color(0xFFFFF176) : const Color(0xFF1976D2),
              decoration: TextDecoration.underline,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
      ));
      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastIndex),
        style: TextStyle(color: msg.isMe ? AppColors.onPrimary : AppColors.onSurface),
      ));
    }

    return Text.rich(TextSpan(children: spans));
  }
}

