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
import 'package:diu_ride/core/utils/direct_call_service.dart';
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
  final String? peerId;

  const ChatScreen({
    super.key,
    required this.rideId,
    this.driverName = 'Ride Companion',
    this.peerName,
    this.vehicleModel = 'Campus Ride',
    this.peerPhone,
    this.peerRole,
    this.peerId,
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

  // Realtime peer typing indicator state
  bool _isPeerTyping = false;
  Timer? _typingTimer;
  Timer? _debounceTypingTimer;

  String get baseRideId {
    if (widget.rideId.contains('__')) {
      return widget.rideId.split('__')[0];
    }
    return widget.rideId;
  }

  String get effectiveChatId {
    if (widget.rideId.contains('__')) {
      return widget.rideId;
    }
    final currentUserId = ref.read(authNotifierProvider).user?.id ?? '';
    final pId = widget.peerId;
    if (pId != null && pId.isNotEmpty && currentUserId.isNotEmpty && pId != currentUserId) {
      final sorted = [currentUserId.trim(), pId.trim()]..sort();
      return '${widget.rideId}__${sorted[0]}__${sorted[1]}';
    }
    return widget.rideId;
  }

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
  String? _resolvedPeerPhone;

  final List<String> _quickReplies = const [
    '📍 At pickup point',
    '🏍️ On my way!',
    '⏱️ Arriving in 2 mins',
    '🚦 Stuck in traffic',
    '👋 Where are you?',
    '✅ Thank you!',
  ];

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatDateDivider(DateTime dt) {
    final now = DateTime.now();
    if (_isSameDay(dt, now)) return 'Today';
    if (_isSameDay(dt, now.subtract(const Duration(days: 1)))) return 'Yesterday';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  @override
  void initState() {
    super.initState();
    _messageController.addListener(_onMessageInputChanged);
    Future.microtask(() {
      _loadSessionStatus();
      _listenWebSocketSession();
    });
  }

  void _onMessageInputChanged() {
    _debounceTypingTimer?.cancel();
    _debounceTypingTimer = Timer(const Duration(milliseconds: 300), () {
      final isTyping = _messageController.text.trim().isNotEmpty;
      _sendTypingEvent(isTyping);
    });
  }

  void _sendTypingEvent(bool isTyping) {
    try {
      final user = ref.read(authNotifierProvider).user;
      final ws = ref.read(webSocketClientProvider);
      ws.send('typing_status', {
        'rideId': effectiveChatId,
        'baseRideId': baseRideId,
        'userId': user?.id ?? '',
        'userName': user?.name ?? 'Companion',
        'peerId': widget.peerId ?? '',
        'isTyping': isTyping,
      });
    } catch (_) {}
  }

  Future<void> _triggerAlertRing() async {
    final user = ref.read(authNotifierProvider).user;
    final senderName = user?.name ?? 'Commuter';
    final ringId = 'ring_${DateTime.now().millisecondsSinceEpoch}';
    final targetId = widget.peerPhone?.isNotEmpty == true
        ? widget.peerPhone!
        : (widget.peerId?.isNotEmpty == true
            ? widget.peerId!
            : (widget.peerName?.isNotEmpty == true ? widget.peerName! : widget.driverName));

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

    ref.read(chatNotifierProvider(effectiveChatId).notifier).sendMessage(
      '🚨 [Alert Ring] Dedicated attention buzz sent to ${widget.displayName}',
      receiverId: widget.peerId,
    );
    _scrollToBottom();
  }

  @override
  void dispose() {
    _debounceTypingTimer?.cancel();
    _typingTimer?.cancel();
    _messageController.removeListener(_onMessageInputChanged);
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
    if (baseRideId == 'campus_community' || baseRideId == 'support_campus') return;
    try {
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 4)));
      final res = await dio.get('$_apiBase/rides/$baseRideId/session-status');
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
            if (d['driverPhone'] != null && d['driverPhone'].toString().isNotEmpty) {
              _resolvedPeerPhone = d['driverPhone'].toString();
            }
            if (d['passengerPhone'] != null && d['passengerPhone'].toString().isNotEmpty && widget.peerRole == 'Passenger') {
              _resolvedPeerPhone = d['passengerPhone'].toString();
            }
          });
          if (_sessionStatus == 'in_progress') {
            _startProgressTimer();
          }
        }
      }

      // Also try fetching ride details to get driverPhone if missing
      if (_resolvedPeerPhone == null && widget.peerPhone == null) {
        try {
          final rRes = await dio.get('$_apiBase/rides/$baseRideId');
          if (rRes.statusCode == 200 && rRes.data is Map) {
            final rData = Map<String, dynamic>.from(rRes.data as Map);
            final phone = rData['driverPhone'] ?? rData['driver_phone'];
            if (mounted && phone != null && phone.toString().isNotEmpty) {
              setState(() {
                _resolvedPeerPhone = phone.toString();
              });
            }
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  void _listenWebSocketSession() {
    final wsClient = ref.read(webSocketClientProvider);
    _wsSessionSub?.cancel();
    _wsSessionSub = wsClient.messages.listen((msg) {
      final event = msg['event'] ?? msg['type'];
      final data = msg['data'] is Map ? Map<String, dynamic>.from(msg['data'] as Map) : msg;
      if (event == 'ride_session_status_changed' && (data['rideId'] == widget.rideId || data['rideId'] == baseRideId || data['rideId'] == effectiveChatId)) {
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

        ref.read(chatNotifierProvider(effectiveChatId).notifier).loadMessages();
        _scrollToBottom();
      } else if ((event == 'typing_status' || event == 'typing') && 
                 (data['rideId'] == effectiveChatId || (data['rideId'] == widget.rideId && data['userId'] == widget.peerId))) {
        final currentUserId = ref.read(authNotifierProvider).user?.id;
        final senderId = data['userId']?.toString();
        if (senderId != null && senderId != currentUserId) {
          final isTyping = data['isTyping'] == true;
          if (mounted) {
            setState(() => _isPeerTyping = isTyping);
            _typingTimer?.cancel();
            if (isTyping) {
              _typingTimer = Timer(const Duration(seconds: 4), () {
                if (mounted) setState(() => _isPeerTyping = false);
              });
            }
          }
        }
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
      await dio.post('$_apiBase/rides/$baseRideId/start', data: {
        'latitude': lat,
        'longitude': lng,
      });

      ref.read(chatNotifierProvider(effectiveChatId).notifier).sendMessage(
        '🚀 [Trip Started] ${user?.name ?? "Rider"} started the ride! Live GPS tracking is active.',
        receiverId: widget.peerId,
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
      ref.read(chatNotifierProvider(effectiveChatId).notifier).loadMessages();
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
    if (baseRideId == 'campus_community' || baseRideId == 'support_campus') {
      return const SizedBox();
    }

    final isInProgress = _sessionStatus == 'in_progress';
    final isCompleted = _sessionStatus == 'completed';
    final isCancelled = _sessionStatus == 'cancelled';

    Color bannerColor;
    Color textColor;
    String statusTitle;
    IconData statusIcon;

    if (isInProgress) {
      bannerColor = const Color(0xFFECFDF5);
      textColor = const Color(0xFF047857);
      final minutes = (_rideElapsedSeconds ~/ 60).toString().padLeft(2, '0');
      final seconds = (_rideElapsedSeconds % 60).toString().padLeft(2, '0');
      statusTitle = 'On Trip ($minutes:$seconds) • ৳${_rideFare.toStringAsFixed(0)}';
      statusIcon = Icons.directions_bike;
    } else if (isCompleted) {
      bannerColor = const Color(0xFFF1F5F9);
      textColor = const Color(0xFF475569);
      statusTitle = 'Ride Completed';
      statusIcon = Icons.check_circle;
    } else if (isCancelled) {
      bannerColor = const Color(0xFFFEF2F2);
      textColor = const Color(0xFFDC2626);
      statusTitle = 'Ride Cancelled';
      statusIcon = Icons.cancel_outlined;
    } else {
      bannerColor = const Color(0xFFFFF7ED);
      textColor = const Color(0xFFC2410C);
      statusTitle = 'Ride Confirmed • ৳${_rideFare.toStringAsFixed(0)}';
      statusIcon = Icons.schedule;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: bannerColor,
        border: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 0.8)),
      ),
      child: Row(
        children: [
          Icon(statusIcon, size: 14, color: textColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$statusTitle  ($_originName ➔ $_destinationName)',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          InkWell(
            onTap: _showTripManagementSheet,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: textColor.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Options',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textColor),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.keyboard_arrow_down, size: 14, color: textColor),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showTripManagementSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isInProgress = _sessionStatus == 'in_progress';
        final isCompleted = _sessionStatus == 'completed';
        final isCancelled = _sessionStatus == 'cancelled';
        final minutes = (_rideElapsedSeconds ~/ 60).toString().padLeft(2, '0');
        final seconds = (_rideElapsedSeconds % 60).toString().padLeft(2, '0');

        return Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Trip Details & Controls',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isInProgress ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isInProgress ? 'ACTIVE ($minutes:$seconds)' : _sessionStatus.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isInProgress ? const Color(0xFF16A34A) : const Color(0xFF475569),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.trip_origin, size: 14, color: Color(0xFF10B981)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_originName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(width: 2, height: 16, color: const Color(0xFFCBD5E1)),
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 14, color: Color(0xFFEF4444)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_destinationName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        ),
                        Text('৳${_rideFare.toStringAsFixed(0)}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildStatusPill(label: 'Driver Ready', isConfirmed: _riderConfirmed),
                  const SizedBox(width: 8),
                  _buildStatusPill(label: 'Passenger Ready', isConfirmed: _passengerConfirmed),
                ],
              ),
              const SizedBox(height: 14),
              if (!isCompleted && !isCancelled) ...[
                if (!isInProgress) ...[
                  if (!_riderConfirmed || !_passengerConfirmed) ...[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF047857),
                        side: const BorderSide(color: Color(0xFF6EE7B7)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _isLoadingSession
                          ? null
                          : () {
                              Navigator.pop(ctx);
                              _confirmRideSession();
                            },
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('Confirm Ride from My Side', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 8),
                  ],
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _isLoadingSession
                        ? null
                        : () {
                            Navigator.pop(ctx);
                            _startRideSession();
                          },
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('Start Commute (Driver on the way)', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ] else ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _isLoadingSession
                        ? null
                        : () {
                            Navigator.pop(ctx);
                            _completeRideSession();
                          },
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('End Trip (Arrived Safely)', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF0284C7),
                          side: const BorderSide(color: Color(0xFFBAE6FD)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _shareLocation();
                        },
                        icon: const Icon(Icons.my_location, size: 15),
                        label: const Text('Share GPS', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFDC2626),
                          side: const BorderSide(color: Color(0xFFFCA5A5)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showCancelTripDialog();
                        },
                        icon: const Icon(Icons.close, size: 15),
                        label: const Text('Cancel Ride', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Text(
                  isCompleted ? '✓ Ride completed safely and archived.' : '✕ Ride was cancelled.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isCompleted ? const Color(0xFF059669) : const Color(0xFFDC2626),
                  ),
                ),
                if (_cancelReason.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Reason: $_cancelReason',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ],
              ],
            ],
          ),
        );
      },
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
    _sendTypingEvent(false);
    ref.read(chatNotifierProvider(effectiveChatId).notifier).sendMessage(text, receiverId: widget.peerId);
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
    ref.read(chatNotifierProvider(effectiveChatId).notifier).shareLocation(lat, lng, receiverId: widget.peerId);
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
    final chatState = ref.watch(chatNotifierProvider(effectiveChatId));
    final displayName = widget.displayName;

    return Scaffold(
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
            tooltip: 'Direct Call $displayName',
            onPressed: () {
              DirectCallService.showCallOptions(
                context,
                phoneNumber: _resolvedPeerPhone ?? widget.peerPhone ?? '',
                peerName: displayName,
                peerRole: widget.peerRole ?? 'Ride Companion',
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: AppColors.onSurfaceVariant),
            tooltip: 'Trip Options',
            onPressed: _showTripManagementSheet,
          ),
        ],
      ),
      backgroundColor: const Color(0xFFF4F6F8),
      body: Column(
        children: [
          _buildRideSessionControlBar(),
          // Messages list
          Expanded(
            child: chatState.isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : chatState.messages.isEmpty
                    ? _buildEmptyChatIntroCard()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: chatState.messages.length,
                        itemBuilder: (context, index) {
                          final msg = chatState.messages[index];
                          final showDateDivider = index == 0 ||
                              !_isSameDay(msg.timestamp, chatState.messages[index - 1].timestamp);

                          if (_isTripCompletedMessage(msg)) {
                            return Column(
                              children: [
                                if (showDateDivider) _buildDateDivider(msg.timestamp),
                                _buildTripCompletedBox(msg),
                              ],
                            );
                          }

                          return Column(
                            crossAxisAlignment:
                                msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              if (showDateDivider) _buildDateDivider(msg.timestamp),
                              Align(
                                alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  constraints: BoxConstraints(
                                    maxWidth: MediaQuery.of(context).size.width * 0.78,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: msg.isMe
                                        ? const LinearGradient(
                                            colors: [Color(0xFFE65100), Color(0xFFFF6D00)],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          )
                                        : null,
                                    color: msg.isMe ? null : Colors.white,
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(18),
                                      topRight: const Radius.circular(18),
                                      bottomLeft: Radius.circular(msg.isMe ? 18 : 3),
                                      bottomRight: Radius.circular(msg.isMe ? 3 : 18),
                                    ),
                                    border: msg.isMe ? null : Border.all(color: const Color(0xFFE5E7EB)),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.04),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
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
                                            color: const Color(0xFFE65100),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
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
                                            style: TextStyle(
                                              color: msg.isMe
                                                  ? Colors.white.withOpacity(0.85)
                                                  : const Color(0xFF9CA3AF),
                                              fontSize: 10,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          if (msg.isMe) ...[
                                            const SizedBox(width: 4),
                                            const Icon(
                                              Icons.done_all,
                                              size: 14,
                                              color: Colors.white,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
          ),

          // Animated Peer Typing Indicator Bubble
          if (_isPeerTyping)
            Align(
              alignment: Alignment.centerLeft,
              child: _TypingBubbleIndicator(peerName: displayName),
            ),

          // Quick commute suggestion chips bar
          Container(
            height: 40,
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _quickReplies.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (ctx, i) {
                final chip = _quickReplies[i];
                return InkWell(
                  onTap: () {
                    _messageController.text = chip;
                    _sendMessage();
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      chip,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF374151),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),

          // Message input bar
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x0A000000),
                    blurRadius: 8,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.my_location, color: Color(0xFFE65100)),
                    tooltip: 'Share Live Campus GPS Location',
                    onPressed: _shareLocation,
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _messageController,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(
                                hintText: 'Type a message to companion...',
                                hintStyle: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13.5),
                                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                border: InputBorder.none,
                              ),
                              onSubmitted: (_) => _sendMessage(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE65100), Color(0xFFFF6D00)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFE65100).withOpacity(0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                      tooltip: 'Send Message',
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

  Widget _buildDateDivider(DateTime dt) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFE2E8F0),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          _formatDateDivider(dt),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF475569),
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyChatIntroCard() {
    final displayName = widget.displayName;
    final role = widget.peerRole ?? 'Companion';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFE65100), Color(0xFFFF9800)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE65100).withOpacity(0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  displayName.isNotEmpty ? displayName[0].toUpperCase() : 'C',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.verified, size: 16, color: Color(0xFF0284C7)),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFEDD5)),
              ),
              child: Text(
                '$role • ${widget.vehicleModel}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFC2410C),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.shield_outlined, size: 18, color: Color(0xFF10B981)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Verified DIU Commute Chat',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Chat directly to coordinate pickup point, timing, and helmet arrangements. Live coordinates can be shared with the GPS button below.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFE65100),
                    side: const BorderSide(color: Color(0xFFFFCC80)),
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  icon: const Icon(Icons.waving_hand, size: 14),
                  label: const Text('Say Hi', style: TextStyle(fontSize: 12)),
                  onPressed: () {
                    _messageController.text = 'Hi ${displayName.split(" ").first}! 👋';
                    _sendMessage();
                  },
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0284C7),
                    side: const BorderSide(color: Color(0xFFBAE6FD)),
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  icon: const Icon(Icons.my_location, size: 14),
                  label: const Text('Share Location', style: TextStyle(fontSize: 12)),
                  onPressed: _shareLocation,
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF059669),
                    side: const BorderSide(color: Color(0xFFA7F3D0)),
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  icon: const Icon(Icons.phone, size: 14),
                  label: const Text('Call', style: TextStyle(fontSize: 12)),
                  onPressed: () {
                    DirectCallService.showCallOptions(
                      context,
                      phoneNumber: _resolvedPeerPhone ?? widget.peerPhone ?? '',
                      peerName: displayName,
                      peerRole: role,
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingBubbleIndicator extends StatefulWidget {
  final String peerName;

  const _TypingBubbleIndicator({required this.peerName});

  @override
  State<_TypingBubbleIndicator> createState() => _TypingBubbleIndicatorState();
}

class _TypingBubbleIndicatorState extends State<_TypingBubbleIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Widget _buildDot(int index) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        final double progress = (_animController.value - (index * 0.18)) % 1.0;
        final double bounce = (progress >= 0 && progress <= 0.5)
            ? (1.0 - (progress * 2 - 0.5).abs() * 2)
            : 0.0;
        return Transform.translate(
          offset: Offset(0, -bounce * 4.5),
          child: Container(
            width: 6.5,
            height: 6.5,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFE65100).withOpacity(0.55 + (bounce * 0.45)),
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 16, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
          bottomRight: Radius.circular(16),
          bottomLeft: Radius.circular(4),
        ),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${widget.peerName} is typing',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFFE65100),
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(width: 7),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDot(0),
              _buildDot(1),
              _buildDot(2),
            ],
          ),
        ],
      ),
    );
  }
}
