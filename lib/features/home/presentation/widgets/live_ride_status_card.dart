import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/booking/presentation/providers/booking_provider.dart';
import 'package:diu_ride/features/booking/data/models/booking_model.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';
import 'package:diu_ride/features/rides/data/models/vehicle_model.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';
import 'package:diu_ride/features/tracking/presentation/screens/ride_details_tracking_screen.dart';
import 'package:diu_ride/features/chat/presentation/screens/chat_screen.dart';

/// LiveRideStatusCard
/// Displays real-time ride and booking status directly on the Home Screen,
/// keeping ongoing commute status easily visible and instantly accessible.
class LiveRideStatusCard extends ConsumerWidget {
  final Function(int tabIndex) onNavigateTab;

  const LiveRideStatusCard({
    super.key,
    required this.onNavigateTab,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(myBookingsProvider);
    final allRidesAsync = ref.watch(allAvailableRidesProvider);
    final allRides = allRidesAsync.value ?? [];

    // Find active booking or active offered ride
    final activeBooking = bookingsAsync.value?.cast<BookingModel?>().firstWhere(
          (b) => b?.status == BookingStatus.accepted || b?.status == BookingStatus.requested,
          orElse: () => null,
        );

    final currentUser = ref.watch(authNotifierProvider).user;
    final activeOfferedRide = allRides.cast<RideModel?>().firstWhere(
          (r) => (r?.status == RideStatus.active || r?.status == RideStatus.published) &&
                 currentUser != null &&
                 (r?.driverId == currentUser.id || r?.driverId == currentUser.studentId || (currentUser.phone.isNotEmpty && r?.driverPhone == currentUser.phone)),
          orElse: () => null,
        );

    if (activeBooking != null) {
      final matchingRide = allRides.firstWhere(
        (r) => r.id == activeBooking.rideId,
        orElse: () => RideModel(
          id: activeBooking.rideId,
          driverId: 'drv',
          driverName: 'Assigned Rider',
          driverDept: 'CSE',
          vehicle: const VehicleModel(
            id: 'veh_01',
            type: VehicleType.bike,
            modelName: 'Motorbike',
            color: 'Black',
            licensePlate: 'Dhaka Metro',
          ),
          originName: activeBooking.pickupPoint,
          originLat: 23.8765,
          originLng: 90.3204,
          destinationName: activeBooking.dropoffPoint,
          destinationLat: 23.8728,
          destinationLng: 90.3984,
          departureTime: DateTime.now(),
          farePerSeat: activeBooking.totalFare,
          totalSeats: 1,
          availableSeats: 0,
        ),
      );

      final isConfirmed = activeBooking.status == BookingStatus.accepted;

      return Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isConfirmed ? const Color(0xFF4CAF50).withOpacity(0.4) : const Color(0xFFFF9800).withOpacity(0.4),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: (isConfirmed ? const Color(0xFF4CAF50) : const Color(0xFFFF9800)).withOpacity(0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isConfirmed ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isConfirmed ? const Color(0xFF2E7D32) : const Color(0xFFE65100),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isConfirmed ? 'CONFIRMED COMMUTE' : 'SEAT REQUESTED',
                        style: TextStyle(
                          color: isConfirmed ? const Color(0xFF2E7D32) : const Color(0xFFE65100),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  '৳${activeBooking.totalFare.toInt()}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFE65100),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.two_wheeler, size: 20, color: Color(0xFFE65100)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        matchingRide.driverName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      Text(
                        'Route: ${activeBooking.pickupPoint} ➔ ${activeBooking.dropoffPoint}',
                        style: TextStyle(color: Colors.grey[700], fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => RideDetailsTrackingScreen(rideId: activeBooking.rideId),
                        ),
                      );
                    },
                    icon: const Icon(Icons.location_on, size: 15),
                    label: const Text('Track Live GPS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65100),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          rideId: activeBooking.rideId,
                          peerName: matchingRide.driverName,
                          driverName: matchingRide.driverName,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.chat_bubble_outline, size: 15),
                  label: const Text('Chat & Ring', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFE65100),
                    side: const BorderSide(color: Color(0xFFE65100)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (activeOfferedRide != null) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF2E7D32).withOpacity(0.4), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2E7D32).withOpacity(0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF2E7D32),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'ACTIVE RIDER POOL',
                        style: TextStyle(
                          color: Color(0xFF2E7D32),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  '৳${activeOfferedRide.farePerSeat.toInt()} / seat',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF2E7D32),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Your Ride: ${activeOfferedRide.originName} ➔ ${activeOfferedRide.destinationName}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => RideDetailsTrackingScreen(rideId: activeOfferedRide.id),
                        ),
                      );
                    },
                    icon: const Icon(Icons.share_location, size: 15),
                    label: const Text('Live Trip Tracking', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () => onNavigateTab(3),
                  icon: const Icon(Icons.message, size: 15),
                  label: const Text('Messages', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2E7D32),
                    side: const BorderSide(color: Color(0xFF2E7D32)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Default status when no active ride: Realtime status badge
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: Color(0xFF10B981),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Campus Network Live Syncing',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
                Text(
                  'Realtime messages, rings & live peer tracking active',
                  style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () => onNavigateTab(1),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Rides',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFE65100),
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 14, color: Color(0xFFE65100)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
