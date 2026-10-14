import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/booking/data/models/booking_model.dart';
import 'package:diu_ride/features/booking/presentation/providers/booking_provider.dart';
import 'package:diu_ride/features/chat/data/models/campus_conversation_model.dart';
import 'package:diu_ride/features/chat/presentation/providers/chat_provider.dart';
import 'package:diu_ride/features/chat/presentation/screens/chat_screen.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';
import 'package:diu_ride/features/rides/data/models/vehicle_model.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';
import 'package:diu_ride/core/services/notification_sound_service.dart';
import 'package:diu_ride/core/utils/direct_call_service.dart';

class CampusMessagesScreen extends ConsumerStatefulWidget {
  final VoidCallback onExploreRides;

  const CampusMessagesScreen({
    super.key,
    required this.onExploreRides,
  });

  @override
  ConsumerState<CampusMessagesScreen> createState() => _CampusMessagesScreenState();
}

class _CampusMessagesScreenState extends ConsumerState<CampusMessagesScreen> {
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authNotifierProvider).user;
    final convosAsync = ref.watch(campusConversationsProvider);
    final myBookingsAsync = ref.watch(myBookingsProvider);
    final allRidesAsync = ref.watch(allAvailableRidesProvider);
    final ridesRepo = ref.watch(ridesRepositoryProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Campus Messages & Calls'),
        backgroundColor: AppColors.surface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.primary),
            tooltip: 'Refresh conversations',
            onPressed: () {
              ref.invalidate(campusConversationsProvider);
              ref.invalidate(myBookingsProvider);
              ref.invalidate(allAvailableRidesProvider);
              setState(() {});
            },
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            ref.invalidate(campusConversationsProvider);
            ref.invalidate(myBookingsProvider);
            ref.invalidate(allAvailableRidesProvider);
            setState(() {});
          },
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24, top: 8),
            children: [
              // Section Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      'Messages',
                      style: AppTypography.headlineSm.copyWith(fontWeight: FontWeight.bold, fontSize: 19),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle, size: 8, color: Color(0xFF10B981)),
                          SizedBox(width: 4),
                          Text(
                            'Active Peers',
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Central & Realtime Messenger Conversations (Sorted with newest at top)
              convosAsync.when(
                data: (convos) {
                  if (convos.isNotEmpty) {
                    final sorted = List<CampusConversationModel>.from(convos);
                    sorted.sort((a, b) => (b.lastTimestamp).compareTo(a.lastTimestamp));
                    return Column(
                      children: sorted.map((c) => _buildUnifiedConversationTile(c)).toList(),
                    );
                  }

                  // Fallback: local bookings & offered rides
                  return myBookingsAsync.when(
                    data: (bookings) {
                      final allRides = allRidesAsync.value ?? [];
                      return FutureBuilder<List<RideModel>>(
                        future: ridesRepo.getMyOfferedRides(user?.id ?? ''),
                        builder: (context, snapshot) {
                          final myOfferedRides = snapshot.data ?? [];
                          if (bookings.isEmpty && myOfferedRides.isEmpty) {
                            return _buildEmptyState();
                          }
                          return Column(
                            children: [
                              if (bookings.isNotEmpty)
                                ...bookings.map((booking) {
                                  final ride = allRides.firstWhere(
                                    (r) => r.id == booking.rideId,
                                    orElse: () => RideModel(
                                      id: booking.rideId,
                                      driverId: 'driver',
                                      driverName: 'Campus Driver',
                                      driverDept: 'DIU Driver',
                                      driverRating: 5.0,
                                      driverRideCount: 1,
                                      originName: booking.pickupPoint,
                                      originSubtitle: 'Pickup',
                                      originLat: 23.8769,
                                      originLng: 90.3204,
                                      destinationName: booking.dropoffPoint,
                                      destinationSubtitle: 'Destination',
                                      destinationLat: 23.8710,
                                      destinationLng: 90.3800,
                                      departureTime: DateTime.now(),
                                      farePerSeat: booking.totalFare,
                                      totalSeats: 1,
                                      availableSeats: 0,
                                      vehicle: const VehicleModel(
                                        id: 'v_ride',
                                        type: VehicleType.bike,
                                        modelName: 'Campus Commute',
                                        color: 'Green',
                                        licensePlate: 'DIU Verified',
                                        hasAc: false,
                                      ),
                                      distanceKm: 12.0,
                                    ),
                                  );
                                  return _buildPassengerConversationTile(booking, ride);
                                }),
                              if (myOfferedRides.isNotEmpty)
                                ...myOfferedRides.map((ride) => _DriverRideConversationsSection(ride: ride)),
                            ],
                          );
                        },
                      );
                    },
                    loading: () => const Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                    ),
                    error: (_, __) => _buildEmptyState(),
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                ),
                error: (e, _) => myBookingsAsync.when(
                  data: (bookings) {
                    if (bookings.isEmpty) return _buildEmptyState();
                    return Column(
                      children: bookings.map((b) => _buildPassengerConversationTile(b, allRidesAsync.value?.firstWhere((r) => r.id == b.rideId, orElse: () => allRidesAsync.value!.first) ?? allRidesAsync.value!.first)).toList(),
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
                  error: (_, __) => _buildEmptyState(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _ringPeer(
    BuildContext context,
    String peerName,
    String rideId, {
    String? peerPhone,
    String? peerId,
  }) async {
    final user = ref.read(authNotifierProvider).user;
    final currentUser = user?.name ?? 'Fellow Student';
    final ringId = 'ring_${DateTime.now().millisecondsSinceEpoch}';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: const Color(0xFFFF9500).withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.notifications_active, color: Color(0xFFFF9500), size: 34),
            ),
            const SizedBox(height: 14),
            Text('Ringing $peerName...', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            const SizedBox(height: 8),
            Text(
              'Dedicated alert buzzer is ringing on $peerName\'s phone. Tap Stop to cancel.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD32F2F),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.call_end, size: 18),
                label: const Text('Stop Ringing', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () async {
                  NotificationSoundService.stopRinging();
                  try {
                    await ref.read(ridesRepositoryProvider).stopAlertRing(
                      targetUserId: peerName,
                      senderId: user?.id,
                      ringId: ringId,
                    );
                  } catch (_) {}
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
            ),
          ],
        ),
      ),
    );

    try {
      await ref.read(ridesRepositoryProvider).triggerAlertRing(
        targetUserId: (peerId != null && peerId.isNotEmpty)
            ? peerId
            : ((peerPhone != null && peerPhone.isNotEmpty) ? peerPhone : peerName),
        targetName: peerName,
        senderId: user?.id ?? '',
        senderName: currentUser,
        rideId: rideId,
        ringId: ringId,
        message: '🚨 Urgent: $currentUser is ringing you for pickup!',
      );
    } catch (_) {}
  }

  Widget _buildUnifiedConversationTile(CampusConversationModel c) {
    final isPassenger = c.peerRole.toLowerCase().contains('passenger');
    final avatarColor = isPassenger ? const Color(0xFF0288D1) : const Color(0xFFE65100);
    final initialLetter = c.peerName.isNotEmpty ? c.peerName[0].toUpperCase() : (isPassenger ? 'P' : 'D');

    // Messenger style relative time formatting
    String timeStr = '';
    if (c.lastTimestamp.isNotEmpty) {
      try {
        final dt = DateTime.parse(c.lastTimestamp).toLocal();
        final now = DateTime.now();
        final diff = now.difference(dt);
        if (diff.inMinutes < 1) {
          timeStr = 'Now';
        } else if (diff.inMinutes < 60) {
          timeStr = '${diff.inMinutes}m';
        } else if (diff.inHours < 24) {
          timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        } else {
          timeStr = '${dt.day}/${dt.month}';
        }
      } catch (_) {
        timeStr = '';
      }
    }

    final hasUnread = c.unreadCount > 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                rideId: c.rideId,
                peerName: c.peerName,
                vehicleModel: c.vehicleModel,
                peerPhone: c.peerPhone.isNotEmpty ? c.peerPhone : null,
                peerRole: c.peerRole,
                peerId: c.peerId,
              ),
            ),
          ).then((_) {
            ref.invalidate(campusConversationsProvider);
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Color(0xFFF3F4F6), width: 1),
            ),
          ),
          child: Row(
            children: [
              // 1. Messenger Circular Avatar with active green dot
              Stack(
                children: [
                  CircleAvatar(
                    radius: 25,
                    backgroundColor: avatarColor.withOpacity(0.14),
                    child: Text(
                      initialLetter,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: avatarColor,
                        fontSize: 19,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),

              // 2. Name & Inner message short part
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            c.peerName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: hasUnread ? FontWeight.w800 : FontWeight.w600,
                              color: const Color(0xFF111827),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.verified, size: 14, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: avatarColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            c.peerRole,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: avatarColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.lastMessage.isNotEmpty ? c.lastMessage : 'Tap to open chat',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w400,
                              color: hasUnread ? const Color(0xFF111827) : const Color(0xFF6B7280),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (timeStr.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(
                            '• $timeStr',
                            style: TextStyle(
                              fontSize: 11,
                              color: hasUnread ? AppColors.primary : const Color(0xFF9CA3AF),
                              fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // 3. Trailing Quick Actions (Call & Ring)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasUnread)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.all(5),
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${c.unreadCount}',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.call, size: 19, color: Color(0xFF2E7D32)),
                    tooltip: 'Call ${c.peerName}',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () {
                      DirectCallService.showCallOptions(
                        context,
                        peerName: c.peerName,
                        phoneNumber: c.peerPhone.isNotEmpty ? c.peerPhone : '01712345678',
                        peerRole: c.peerRole,
                        peerDept: c.peerDept,
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.notifications_active, size: 19, color: Color(0xFFFF9500)),
                    tooltip: 'Alert Ring',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () => _ringPeer(
                      context,
                      c.peerName,
                      c.rideId,
                      peerPhone: c.peerPhone,
                      peerId: c.peerId,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPassengerConversationTile(BookingModel booking, RideModel ride) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                rideId: booking.rideId,
                peerName: ride.driverName,
                vehicleModel: ride.vehicle.modelName,
                peerPhone: ride.driverPhone,
                peerRole: 'Driver',
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6), width: 1)),
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 25,
                    backgroundColor: const Color(0xFFE65100).withOpacity(0.14),
                    child: Text(
                      ride.driverName.isNotEmpty ? ride.driverName[0].toUpperCase() : 'D',
                      style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFE65100), fontSize: 19),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            ride.driverName,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.verified, size: 14, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE65100).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Biker',
                            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFFE65100)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Trip: ${booking.pickupPoint} ➔ ${booking.dropoffPoint}',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.call, size: 19, color: Color(0xFF2E7D32)),
                    tooltip: 'Call Driver',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () {
                      DirectCallService.showCallOptions(
                        context,
                        peerName: ride.driverName,
                        phoneNumber: ride.driverPhone ?? '01712345678',
                        peerRole: 'Driver',
                        peerDept: ride.driverDept,
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.notifications_active, size: 19, color: Color(0xFFFF9500)),
                    tooltip: 'Alert Ring Driver',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () => _ringPeer(context, ride.driverName, booking.rideId, peerPhone: ride.driverPhone),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.chat_bubble_outline,
              size: 36,
              color: AppColors.outline,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No Active Ride Conversations',
            style: AppTypography.headlineSm.copyWith(color: AppColors.onSurface),
          ),
          const SizedBox(height: 6),
          Text(
            'When you book or publish a ride, direct chat and voice call options with fellow DIU students will appear here.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: widget.onExploreRides,
            icon: const Icon(Icons.search, size: 18),
            label: const Text('Find Rides Departing Soon'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverRideConversationsSection extends ConsumerWidget {
  final RideModel ride;
  const _DriverRideConversationsSection({required this.ride});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(rideBookingsProvider(ride.id));

    return bookingsAsync.when(
      data: (bookings) {
        if (bookings.isEmpty) return const SizedBox();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: bookings.map((booking) {
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        rideId: ride.id,
                        peerName: booking.passengerName,
                        vehicleModel: 'Passenger Chat',
                        peerPhone: booking.passengerPhone,
                        peerRole: 'Passenger',
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6), width: 1)),
                  ),
                  child: Row(
                    children: [
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 25,
                            backgroundColor: const Color(0xFF0288D1).withOpacity(0.14),
                            child: Text(
                              booking.passengerName.isNotEmpty ? booking.passengerName[0].toUpperCase() : 'P',
                              style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0288D1), fontSize: 19),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 13,
                              height: 13,
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    booking.passengerName,
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.verified, size: 14, color: AppColors.primary),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0288D1).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'Passenger',
                                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF0288D1)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Pickup: ${booking.pickupPoint} ➔ Dropoff: ${booking.dropoffPoint}',
                              style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.call, size: 19, color: Color(0xFF2E7D32)),
                            tooltip: 'Call Passenger',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            onPressed: () {
                              DirectCallService.showCallOptions(
                                context,
                                peerName: booking.passengerName,
                                phoneNumber: booking.passengerPhone.isNotEmpty ? booking.passengerPhone : '01712345678',
                                peerRole: 'Passenger',
                                peerDept: booking.passengerDept,
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.notifications_active, size: 19, color: Color(0xFFFF9500)),
                            tooltip: 'Alert Ring Passenger',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            onPressed: () async {
                              final currentUser = ref.read(authNotifierProvider).user?.name ?? 'Rider';
                              final ringId = 'ring_${DateTime.now().millisecondsSinceEpoch}';
                              final authUser = ref.read(authNotifierProvider).user;

                              showDialog(
                                context: context,
                                barrierDismissible: false,
                                builder: (ctx) => AlertDialog(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                  backgroundColor: Colors.white,
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 68,
                                        height: 68,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFF9500).withOpacity(0.15),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.notifications_active, color: Color(0xFFFF9500), size: 34),
                                      ),
                                      const SizedBox(height: 14),
                                      Text(
                                        'Ringing ${booking.passengerName}...',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Dedicated alert buzzer is ringing on their phone. Tap Stop to cancel.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                                      ),
                                      const SizedBox(height: 20),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFFD32F2F),
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                          ),
                                          icon: const Icon(Icons.call_end, size: 18),
                                          label: const Text('Stop Ringing', style: TextStyle(fontWeight: FontWeight.bold)),
                                          onPressed: () async {
                                            NotificationSoundService.stopRinging();
                                            try {
                                              await ref.read(ridesRepositoryProvider).stopAlertRing(
                                                targetUserId: booking.passengerPhone.isNotEmpty ? booking.passengerPhone : booking.passengerName,
                                                senderId: authUser?.id,
                                                ringId: ringId,
                                              );
                                            } catch (_) {}
                                            if (ctx.mounted) Navigator.pop(ctx);
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );

                              try {
                                await ref.read(ridesRepositoryProvider).triggerAlertRing(
                                  targetUserId: booking.passengerPhone.isNotEmpty ? booking.passengerPhone : booking.passengerName,
                                  targetName: booking.passengerName,
                                  senderId: authUser?.id ?? '',
                                  senderName: currentUser,
                                  rideId: ride.id,
                                  ringId: ringId,
                                  message: '🚨 Urgent: Rider $currentUser is buzzing you for pickup!',
                                );
                              } catch (_) {}
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
      loading: () => const SizedBox(),
      error: (_, __) => const SizedBox(),
    );
  }
}
