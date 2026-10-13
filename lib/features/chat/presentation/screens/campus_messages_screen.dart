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
import 'package:diu_ride/features/safety/presentation/widgets/campus_voice_call_dialog.dart';
import 'package:diu_ride/core/services/notification_sound_service.dart';

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
              // 1. DIU Campus Rider Community Public Room (All Bikers & Commuters)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE65100), Color(0xFFF57C00)],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE65100).withOpacity(0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.white,
                      child: Icon(Icons.forum, color: Color(0xFFE65100), size: 22),
                    ),
                    title: const Row(
                      children: [
                        Text('DIU Rider Community', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        SizedBox(width: 6),
                        Icon(Icons.stars, size: 16, color: Colors.amber),
                      ],
                    ),
                    subtitle: const Text(
                      'All Bikers & Commuters • Post ride asks & live updates',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('Open Room', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ChatScreen(
                            rideId: 'campus_community',
                            driverName: 'DIU Rider Community',
                            vehicleModel: 'All Bikers & Commuters',
                            peerPhone: 'Public Campus Channel',
                            peerRole: 'Community Group',
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // 3. Official Campus Support Desk Tile
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [
                      BoxShadow(color: AppColors.cardShadow, blurRadius: 4, offset: Offset(0, 1)),
                    ],
                  ),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.primaryContainer,
                      child: Icon(Icons.support_agent, color: Colors.white, size: 20),
                    ),
                    title: Row(
                      children: [
                        Text('DIU Campus Support Desk', style: AppTypography.bodyLgMedium),
                        const SizedBox(width: 6),
                        const Icon(Icons.verified, size: 14, color: AppColors.primary),
                      ],
                    ),
                    subtitle: Text(
                      'Commute queries, route assistance & student support',
                      style: AppTypography.labelSm.copyWith(color: AppColors.onSurfaceVariant),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: AppColors.outline),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ChatScreen(
                            rideId: 'support_campus',
                            driverName: 'DIU Campus Support',
                            vehicleModel: 'Official Helpdesk',
                            peerPhone: '01847140000',
                            peerRole: 'Campus Support',
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Section Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Text(
                      'Active Commute Conversations',
                      style: AppTypography.bodyLgMedium.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Live Peer Sync',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primary),
                      ),
                    ),
                  ],
                ),
              ),

              // 3. Central & Realtime Conversations (All Passengers & Bikers)
              convosAsync.when(
                data: (convos) {
                  if (convos.isNotEmpty) {
                    return Column(
                      children: convos.map((c) => _buildUnifiedConversationTile(c)).toList(),
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

  void _ringPeer(BuildContext context, String peerName, String rideId) async {
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
        targetUserId: peerName,
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
    final avatarColor = isPassenger ? const Color(0xFF0288D1) : AppColors.primary;
    final initialLetter = c.peerName.isNotEmpty ? c.peerName[0].toUpperCase() : (isPassenger ? 'P' : 'D');

    Color statusBg = const Color(0xFFFFF3E0);
    Color statusFg = const Color(0xFFE65100);
    final st = c.status.toLowerCase();
    if (st == 'accepted' || st == 'completed') {
      statusBg = const Color(0xFFE8F5E9);
      statusFg = const Color(0xFF2E7D32);
    } else if (st == 'inquired') {
      statusBg = const Color(0xFFE1F5FE);
      statusFg = const Color(0xFF0288D1);
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: AppColors.cardShadow, blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: avatarColor.withOpacity(0.15),
                child: Text(
                  initialLetter,
                  style: TextStyle(fontWeight: FontWeight.bold, color: avatarColor, fontSize: 16),
                ),
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
                            c.peerName,
                            style: AppTypography.bodyMdMedium.copyWith(fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.verified, size: 14, color: AppColors.primary),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusBg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            c.status.toUpperCase(),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: statusFg,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${c.peerRole} • ${c.peerDept}',
                      style: AppTypography.labelSm.copyWith(color: AppColors.outline),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Route snippet
          Row(
            children: [
              const Icon(Icons.route, size: 13, color: AppColors.outline),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  c.route.isNotEmpty ? c.route : '${c.origin} ➔ ${c.destination}',
                  style: AppTypography.labelSm.copyWith(color: AppColors.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (c.fare > 0) ...[
                const SizedBox(width: 4),
                Text(
                  '৳${c.fare.toInt()}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.primary),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          // Latest message snippet
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 13,
                  color: c.unreadCount > 0 ? AppColors.primary : AppColors.outline,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    c.lastMessage,
                    style: TextStyle(
                      fontSize: 12,
                      color: c.unreadCount > 0 ? AppColors.onSurface : AppColors.onSurfaceVariant,
                      fontWeight: c.unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (c.unreadCount > 0)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${c.unreadCount} new',
                      style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          rideId: c.rideId,
                          peerName: c.peerName,
                          vehicleModel: c.vehicleModel,
                          peerPhone: c.peerPhone.isNotEmpty ? c.peerPhone : null,
                          peerRole: c.peerRole,
                        ),
                      ),
                    ).then((_) {
                      ref.invalidate(campusConversationsProvider);
                    });
                  },
                  icon: const Icon(Icons.chat_bubble_outline, size: 15),
                  label: const Text('Chat', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    CampusVoiceCallDialog.show(
                      context,
                      peerName: c.peerName,
                      peerPhone: c.peerPhone.isNotEmpty ? c.peerPhone : '01712345678',
                      peerRole: c.peerRole,
                      peerDept: c.peerDept,
                    );
                  },
                  icon: const Icon(Icons.call, size: 15),
                  label: const Text('Voice Call', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _ringPeer(context, c.peerName, c.rideId),
                icon: const Icon(Icons.notifications_active, color: Color(0xFFFF9500), size: 20),
                tooltip: 'Alert Ring (${c.peerName})',
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFFFF3E0),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPassengerConversationTile(BookingModel booking, RideModel ride) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: AppColors.cardShadow, blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.primaryContainer,
                child: Text(
                  ride.driverName.isNotEmpty ? ride.driverName[0].toUpperCase() : 'D',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          ride.driverName,
                          style: AppTypography.bodyMdMedium.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.verified, size: 14, color: AppColors.primary),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: booking.status == BookingStatus.accepted
                                ? const Color(0xFFE8F5E9)
                                : const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            booking.status.name.toUpperCase(),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: booking.status == BookingStatus.accepted
                                  ? const Color(0xFF2E7D32)
                                  : const Color(0xFFE65100),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'Driver • ${ride.vehicle.modelName}',
                      style: AppTypography.labelSm.copyWith(color: AppColors.outline),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Trip: ${booking.pickupPoint} ➔ ${booking.dropoffPoint}',
            style: AppTypography.labelSm.copyWith(color: AppColors.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
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
                  icon: const Icon(Icons.chat_bubble_outline, size: 15),
                  label: const Text('Chat', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    CampusVoiceCallDialog.show(
                      context,
                      peerName: ride.driverName,
                      peerPhone: ride.driverPhone ?? '01712345678',
                      peerRole: 'Driver',
                      peerDept: ride.driverDept,
                    );
                  },
                  icon: const Icon(Icons.call, size: 15),
                  label: const Text('Voice Call', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _ringPeer(context, ride.driverName, booking.rideId),
                icon: const Icon(Icons.notifications_active, color: Color(0xFFFF9500), size: 20),
                tooltip: 'Alert Ring Driver (জরুরি রিং)',
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFFFF3E0),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
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
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(color: AppColors.cardShadow, blurRadius: 4, offset: Offset(0, 1)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: AppColors.primaryFixed,
                        child: Text(
                          booking.passengerName.isNotEmpty ? booking.passengerName[0].toUpperCase() : 'P',
                          style: AppTypography.bodyMdMedium.copyWith(color: AppColors.onPrimaryFixed),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  booking.passengerName,
                                  style: AppTypography.bodyMdMedium.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: booking.status == BookingStatus.accepted
                                        ? const Color(0xFFE8F5E9)
                                        : const Color(0xFFFFF3E0),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    booking.status.name.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: booking.status == BookingStatus.accepted
                                          ? const Color(0xFF2E7D32)
                                          : const Color(0xFFE65100),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              'Passenger • ${booking.passengerDept} • ${booking.seatsBooked} Seat(s)',
                              style: AppTypography.labelSm.copyWith(color: AppColors.outline),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pickup: ${booking.pickupPoint} ➔ Dropoff: ${booking.dropoffPoint}',
                    style: AppTypography.labelSm.copyWith(color: AppColors.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
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
                          icon: const Icon(Icons.chat_bubble_outline, size: 15),
                          label: const Text('Chat', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            CampusVoiceCallDialog.show(
                              context,
                              peerName: booking.passengerName,
                              peerPhone: booking.passengerPhone,
                              peerRole: 'Passenger',
                              peerDept: booking.passengerDept,
                            );
                          },
                          icon: const Icon(Icons.call, size: 15),
                          label: const Text('Voice Call', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2E7D32),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
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
                                    'Dedicated alert buzzer is ringing on ${booking.passengerName}\'s phone. Tap Stop to cancel.',
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
                                            targetUserId: booking.passengerName,
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
                        icon: const Icon(Icons.notifications_active, color: Color(0xFFFF9500), size: 20),
                        tooltip: 'Alert Ring Passenger (জরুরি রিং)',
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFFFFF3E0),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                ],
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
