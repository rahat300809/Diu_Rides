import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/chat/presentation/screens/chat_screen.dart';
import 'package:diu_ride/features/rides/data/models/passenger_request_model.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';

class RiderStudentRequestsSection extends ConsumerWidget {
  final VoidCallback onSeeAll;

  const RiderStudentRequestsSection({
    super.key,
    required this.onSeeAll,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(passengerRequestsProvider);
    final user = ref.watch(authNotifierProvider).user;
    final ridesRepo = ref.watch(ridesRepositoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.hail_rounded, color: Color(0xFFE65100), size: 18),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Student Pickup Requests',
                    style: AppTypography.headlineSm.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: const Color(0xFF141416),
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: onSeeAll,
                child: Text(
                  'Explore All',
                  style: AppTypography.labelMd.copyWith(
                    color: const Color(0xFFE65100),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        requestsAsync.when(
          data: (rawRequests) {
            final requests = rawRequests.map((e) {
              if (e is PassengerRequestModel) return e;
              return PassengerRequestModel.fromJson(Map<String, dynamic>.from(e as Map));
            }).where((r) => r.status != 'cancelled' && r.status != 'completed').toList();

            if (requests.isEmpty) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFF0F0F2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Color(0xFF8E8E93), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'No pending student ride requests right now. Publish a ride so peers can book your seat!',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ),
                  ],
                ),
              );
            }

            return SizedBox(
              height: 180,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: requests.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final req = requests[index];
                  final isAccepted = req.isAccepted ||
                      (user != null && req.acceptedByDriverId == user.id);

                  return Container(
                    width: 280,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x0A000000),
                          blurRadius: 10,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 12,
                                  backgroundColor: const Color(0xFFE65100).withOpacity(0.12),
                                  child: Text(
                                    req.passengerName.isNotEmpty ? req.passengerName[0] : 'S',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFE65100),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 120),
                                  child: Text(
                                    req.passengerName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF3E0),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '৳${req.proposedFare.toInt()}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFE65100),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.location_on, size: 14, color: Color(0xFFE65100)),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '${req.pickup} → ${req.dropoff}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Time: ${req.requestedTime}',
                              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            if (isAccepted)
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => ChatScreen(
                                          rideId: req.id,
                                          peerName: req.passengerName,
                                          vehicleModel: 'Motorbike Commute',
                                          peerPhone: req.passengerPhone,
                                          peerRole: 'Passenger',
                                          peerId: req.passengerId,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.chat_bubble_outline, size: 14),
                                  label: const Text('Chat with Passenger', style: TextStyle(fontSize: 11)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF2E7D32),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              )
                            else ...[
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    final currentUserId = user?.id ?? 'drv_peer';
                                    final currentUserName = user?.name ?? 'Campus Biker';
                                    final currentUserPhone = user?.phone ?? '01712345678';

                                    final ok = await ridesRepo.acceptPassengerRequest(
                                      requestId: req.id,
                                      driverId: currentUserId,
                                      driverName: currentUserName,
                                      driverPhone: currentUserPhone,
                                      driverBike: 'Campus Motorcycle',
                                    );

                                    ref.invalidate(passengerRequestsProvider);

                                    if (ok && context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          backgroundColor: const Color(0xFF2E7D32),
                                          content: Text('Accepted! You are commuting with ${req.passengerName}.'),
                                        ),
                                      );
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => ChatScreen(
                                            rideId: req.id,
                                            peerName: req.passengerName,
                                            vehicleModel: 'Motorbike Commute',
                                            peerPhone: req.passengerPhone,
                                            peerRole: 'Passenger',
                                            peerId: req.passengerId,
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.check, size: 14),
                                  label: const Text('Accept & Give Ride', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFE65100),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator(color: Color(0xFFE65100))),
          ),
          error: (_, __) => const SizedBox.shrink(),
        ),
      ],
    );
  }
}
