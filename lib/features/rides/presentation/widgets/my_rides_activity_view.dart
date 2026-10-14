import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/utils/currency_formatter.dart';
import 'package:diu_ride/core/utils/date_time_utils.dart';
import 'package:diu_ride/core/utils/direct_call_service.dart';
import 'package:diu_ride/features/booking/data/models/booking_model.dart';
import 'package:diu_ride/features/booking/presentation/providers/booking_provider.dart';
import 'package:diu_ride/features/chat/presentation/screens/chat_screen.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';
import 'package:diu_ride/features/rides/presentation/widgets/post_expiry_extension_dialog.dart';

class MyRidesActivityView extends ConsumerStatefulWidget {
  final VoidCallback onOfferRide;

  const MyRidesActivityView({
    super.key,
    required this.onOfferRide,
  });

  @override
  ConsumerState<MyRidesActivityView> createState() => _MyRidesActivityViewState();
}

class _MyRidesActivityViewState extends ConsumerState<MyRidesActivityView> {
  int _activeSegment = 0; // 0 = Posted as Driver, 1 = Booked as Passenger

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Top Sub-segment switcher: Posted as Driver vs Booked as Passenger
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _activeSegment = 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _activeSegment == 0 ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: _activeSegment == 0
                          ? [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.06),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.two_wheeler,
                          size: 15,
                          color: _activeSegment == 0 ? const Color(0xFFE65100) : const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Posted by Me (Driver)',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: _activeSegment == 0 ? FontWeight.bold : FontWeight.w600,
                            color: _activeSegment == 0 ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _activeSegment = 1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _activeSegment == 1 ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: _activeSegment == 1
                          ? [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.06),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.bookmark_outline,
                          size: 15,
                          color: _activeSegment == 1 ? const Color(0xFFE65100) : const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Booked by Me (Rider)',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: _activeSegment == 1 ? FontWeight.bold : FontWeight.w600,
                            color: _activeSegment == 1 ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Content Area
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(myPostedRidesProvider);
              ref.invalidate(myBookingsProvider);
              ref.invalidate(allSystemRidesProvider);
            },
            child: _activeSegment == 0
                ? _buildPostedRidesList()
                : _buildBookedRidesList(),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 1. DRIVER: My Posted Rides
  // ---------------------------------------------------------------------------
  Widget _buildPostedRidesList() {
    final postedAsync = ref.watch(myPostedRidesProvider);

    return postedAsync.when(
      data: (rides) {
        if (rides.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFFFEDD5)),
                    ),
                    child: const Icon(Icons.add_road, size: 36, color: Color(0xFFEA580C)),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No Active Posted Rides',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'You haven\'t posted any rides yet. Share an empty bike seat on your way to DIU and split fuel costs!',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: widget.onOfferRide,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Post a Moto Ride Now', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: rides.length,
          itemBuilder: (ctx, i) => _buildDriverRideCard(rides[i]),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('Failed to load posted rides: $err')),
    );
  }

  Widget _buildDriverRideCard(RideModel ride) {
    final isCompleted = ride.status == RideStatus.completed;
    final isActive = ride.status == RideStatus.active;
    final isCancelled = ride.status == RideStatus.cancelled;

    Color statusColor;
    String statusText;
    if (isCompleted) {
      statusColor = const Color(0xFF64748B);
      statusText = 'COMPLETED';
    } else if (isActive) {
      statusColor = const Color(0xFF0284C7);
      statusText = 'TRIP ON THE WAY';
    } else if (isCancelled) {
      statusColor = const Color(0xFFDC2626);
      statusText = 'CANCELLED';
    } else {
      statusColor = ride.availableSeats < ride.totalSeats ? const Color(0xFFD97706) : const Color(0xFF059669);
      statusText = ride.availableSeats < ride.totalSeats ? 'PASSENGER BOOKED' : 'WAITING FOR RIDERS';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: Status + Time
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(17)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: statusColor,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
                Text(
                  DateTimeUtils.formatTime(ride.departureTime),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Route
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        const SizedBox(height: 3),
                        Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
                        Container(width: 2, height: 26, color: const Color(0xFFD1D5DB)),
                        Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF0F172A))),
                      ],
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ride.originName,
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            ride.destinationName,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          CurrencyFormatter.formatBdt(ride.farePerSeat),
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                        ),
                        Text(
                          '${ride.availableSeats}/${ride.totalSeats} seats open',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Passenger Bookings section for this ride
                _buildRideBookingsSection(ride),

                const SizedBox(height: 12),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                const SizedBox(height: 10),

                // Driver Action Buttons
                Row(
                  children: [
                    if (!isCompleted && !isCancelled) ...[
                      if (!isActive)
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Start This Commute?'),
                                  content: const Text('This will notify all booked passengers that you are on the way and start live tracking.'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not yet')),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Start Now', style: TextStyle(color: Colors.white)),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await ref.read(ridesRepositoryProvider).startRide(ride.id);
                                ref.invalidate(myPostedRidesProvider);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0284C7),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.play_arrow_rounded, size: 16),
                            label: const Text('Start Ride', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        )
                      else
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Complete Commute?'),
                                  content: const Text('Have you safely arrived at the destination? This will archive the ride.'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669)),
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Complete', style: TextStyle(color: Colors.white)),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await ref.read(ridesRepositoryProvider).completeRide(ride.id);
                                ref.invalidate(myPostedRidesProvider);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF059669),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.check_circle, size: 15),
                            label: const Text('Complete Ride', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      const SizedBox(width: 8),
                      // Time Extend Button
                      OutlinedButton.icon(
                        onPressed: () {
                          PostExpiryExtensionDialog.show(
                            context,
                            postId: ride.id,
                            postType: 'ride',
                            title: 'Extend Departure Time',
                            scheduledTimeStr: ride.departureTime.toIso8601String(),
                          ).then((_) {
                            ref.invalidate(myPostedRidesProvider);
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF0F172A),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.more_time, size: 14),
                        label: const Text('Extend', style: TextStyle(fontSize: 11.5)),
                      ),
                      const SizedBox(width: 8),
                      // Delete / Cancel Button
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFDC2626)),
                        tooltip: 'Cancel and Delete Post',
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Delete Posted Ride?'),
                              content: const Text('Are you sure you want to delete this posted ride?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Delete', style: TextStyle(color: Colors.white)),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await ref.read(ridesRepositoryProvider).deleteRide(ride.id);
                            ref.invalidate(myPostedRidesProvider);
                          }
                        },
                      ),
                    ] else ...[
                      // Finished state badge
                      Expanded(
                        child: Text(
                          isCompleted ? '✓ This ride was completed safely.' : '✕ This ride was cancelled.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isCompleted ? const Color(0xFF059669) : const Color(0xFFDC2626),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRideBookingsSection(RideModel ride) {
    final bookingsAsync = ref.watch(rideBookingsProvider(ride.id));

    return bookingsAsync.when(
      data: (bookings) {
        if (bookings.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: Color(0xFF94A3B8)),
                SizedBox(width: 6),
                Text(
                  'No passenger bookings yet. Waiting for riders.',
                  style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Booked Passengers (${bookings.length}):',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
            ),
            const SizedBox(height: 6),
            ...bookings.map((b) => _buildBookingItemForDriver(ride, b)),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildBookingItemForDriver(RideModel ride, BookingModel booking) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: const Color(0xFFE0E7FF),
            child: Text(
              booking.passengerName.isNotEmpty ? booking.passengerName[0].toUpperCase() : 'P',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF4338CA)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${booking.passengerName} (${booking.seatsBooked} seat)',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                ),
                Text(
                  'Pickup: ${booking.pickupPoint}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Chat Button
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline, size: 16, color: Color(0xFF0284C7)),
            tooltip: 'Chat with Rider',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    rideId: ride.id,
                    driverName: ride.driverName,
                    peerName: booking.passengerName,
                    vehicleModel: ride.vehicle.modelName,
                    peerPhone: booking.passengerPhone,
                    peerRole: 'Passenger',
                  ),
                ),
              );
            },
          ),
          // Call Button
          IconButton(
            icon: const Icon(Icons.phone_outlined, size: 16, color: Color(0xFF059669)),
            tooltip: 'Call Rider',
            onPressed: () {
              DirectCallService.showCallOptions(
                context,
                phoneNumber: booking.passengerPhone,
                peerName: booking.passengerName,
                peerRole: 'Passenger',
              );
            },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 2. PASSENGER: My Bookings
  // ---------------------------------------------------------------------------
  Widget _buildBookedRidesList() {
    final bookingsAsync = ref.watch(myBookingsProvider);

    return bookingsAsync.when(
      data: (bookings) {
        if (bookings.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Icon(Icons.bookmark_border, size: 36, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No Active Bookings',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'You haven\'t booked any seats yet. Search available bike rides to commute safely to campus!',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.4),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: bookings.length,
          itemBuilder: (ctx, i) => _buildPassengerBookingCard(bookings[i]),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('Failed to load bookings: $err')),
    );
  }

  Widget _buildPassengerBookingCard(BookingModel booking) {
    Color statusBg;
    Color statusFg;
    String statusLabel;

    switch (booking.status) {
      case BookingStatus.accepted:
        statusBg = const Color(0xFFDCFCE7);
        statusFg = const Color(0xFF16A34A);
        statusLabel = 'CONFIRMED';
        break;
      case BookingStatus.completed:
        statusBg = const Color(0xFFF1F5F9);
        statusFg = const Color(0xFF475569);
        statusLabel = 'COMPLETED';
        break;
      case BookingStatus.cancelled:
      case BookingStatus.rejected:
        statusBg = const Color(0xFFFEE2E2);
        statusFg = const Color(0xFFDC2626);
        statusLabel = booking.status == BookingStatus.cancelled ? 'CANCELLED' : 'REJECTED';
        break;
      case BookingStatus.requested:
      default:
        statusBg = const Color(0xFFFEF3C7);
        statusFg = const Color(0xFFD97706);
        statusLabel = 'REQUESTED';
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: statusFg,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                Text(
                  CurrencyFormatter.formatBdt(booking.totalFare),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Route
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    const SizedBox(height: 3),
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
                    Container(width: 2, height: 24, color: const Color(0xFFD1D5DB)),
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF0F172A))),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        booking.pickupPoint,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        booking.dropoffPoint,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 10),

            // Bottom Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (booking.status == BookingStatus.requested || booking.status == BookingStatus.accepted) ...[
                  OutlinedButton.icon(
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Cancel Booking?'),
                          content: const Text('Are you sure you want to cancel this booking?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Cancel Booking', style: TextStyle(color: Colors.white)),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await ref.read(bookingNotifierProvider.notifier).cancelBooking(booking.id);
                        ref.invalidate(myBookingsProvider);
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      side: const BorderSide(color: Color(0xFFFCA5A5)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.close, size: 14),
                    label: const Text('Cancel', style: TextStyle(fontSize: 11.5)),
                  ),
                  const SizedBox(width: 8),
                ],

                // Chat with driver button
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          rideId: booking.rideId,
                          driverName: 'Driver',
                          peerName: 'Driver',
                          vehicleModel: 'Bike',
                          peerRole: 'Driver',
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.chat_bubble_outline, size: 14),
                  label: const Text('Chat with Driver', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
