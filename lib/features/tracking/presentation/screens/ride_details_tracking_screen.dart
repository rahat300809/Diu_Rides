import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/network/websocket_client.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/features/chat/presentation/screens/chat_screen.dart';
import 'package:diu_ride/features/rating/presentation/widgets/rate_ride_sheet.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';
import 'package:diu_ride/features/rides/data/models/vehicle_model.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';
import 'package:diu_ride/features/safety/presentation/widgets/campus_sos_dialog.dart';
import 'package:diu_ride/features/safety/presentation/widgets/campus_voice_call_dialog.dart';


class RideDetailsTrackingScreen extends ConsumerStatefulWidget {
  final String rideId;

  const RideDetailsTrackingScreen({
    super.key,
    required this.rideId,
  });

  @override
  ConsumerState<RideDetailsTrackingScreen> createState() => _RideDetailsTrackingScreenState();
}

class _RideDetailsTrackingScreenState extends ConsumerState<RideDetailsTrackingScreen> {
  int _seats = 1;
  bool _isReserved = false;
  WebSocketClient? _wsClient;
  StreamSubscription? _wsSub;

  double _driverLat = 23.8778;
  double _driverLng = 90.3235;
  int _etaMinutes = 5;
  double _distanceKm = 1.2;
  final String _roadInfo = 'Cruising along Birulia - Ashulia Road';

  @override
  void initState() {
    super.initState();
    _connectRealtime();
  }

  void _connectRealtime() {
    _wsClient = WebSocketClient();
    _wsClient?.connect();
    _wsSub = _wsClient?.messages.listen((msg) {
      if (msg['event'] == 'driver_location_update') {
        final data = msg['data'] as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _driverLat = (data['latitude'] as num).toDouble();
            _driverLng = (data['longitude'] as num).toDouble();
            _etaMinutes = data['etaMinutes'] as int? ?? _etaMinutes;
            _distanceKm = (data['distanceRemainingKm'] as num?)?.toDouble() ?? _distanceKm;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _wsClient?.dispose();
    super.dispose();
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.inverseSurface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.primaryFixed, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: AppTypography.bodyMd.copyWith(color: AppColors.inverseOnSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ridesAsync = ref.watch(searchRidesResultsProvider);
    final RideModel ride = ridesAsync.maybeWhen(
      data: (list) {
        for (final r in list) {
          if (r.id == widget.rideId) return r;
        }
        return list.isNotEmpty ? list.first : _defaultRide(widget.rideId);
      },
      orElse: () => _defaultRide(widget.rideId),
    );


    final totalFare = (ride.farePerSeat * _seats).toInt();

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            const Icon(Icons.directions_car, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            Text('Details', style: AppTypography.headlineSm),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primaryFixed.withOpacity(0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified, size: 14, color: AppColors.primary),
                const SizedBox(width: 4),
                Text(
                  'DIU Verified',
                  style: AppTypography.labelSm.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. TOP LIVE REALTIME TRACKING VIEW
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Container(
                height: 250,
                decoration: const BoxDecoration(
                  color: Color(0xFFE2EDE4),
                  boxShadow: [
                    BoxShadow(color: AppColors.cardShadow, blurRadius: 10, offset: Offset(0, 3)),
                  ],
                ),
                child: Stack(
                  children: [
                    // Simulated Campus Road Canvas with Live Moving Marker
                    CustomPaint(
                      size: const Size(double.infinity, 250),
                      painter: _TrackingMapPainter(
                        driverLat: _driverLat,
                        driverLng: _driverLng,
                      ),
                    ),

                    // Top Left: Live GPS Active Beacon
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.92),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Live GPS Active',
                              style: AppTypography.labelSm.copyWith(
                                color: AppColors.onSurface,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Top Right: Campus SOS Floating Action Shield
                    Positioned(
                      top: 12,
                      right: 12,
                      child: InkWell(
                        onTap: () {
                          CampusSosDialog.show(
                            context: context,
                            onConfirmed: () {
                              _showToast('Connecting to DIU Smart Campus Proctor Security Hotline...');
                            },
                          );
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.error.withOpacity(0.35),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.local_police, color: Colors.white, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                'Campus SOS',
                                style: AppTypography.labelSm.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Center Animated Moving Driver Car Avatar
                    Center(
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(color: Colors.black26, blurRadius: 6),
                              ],
                            ),
                            child: const Icon(Icons.directions_car, color: Colors.white, size: 18),
                          ),
                        ),
                      ),
                    ),

                    // Floating ETA Glass Pill (Bottom)
                    Positioned(
                      bottom: 12,
                      left: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.94),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: const [
                            BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2)),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryFixed,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.near_me, color: AppColors.onPrimaryFixed, size: 20),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          '$_etaMinutes mins away',
                                          style: AppTypography.labelLg.copyWith(
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text('•', style: AppTypography.labelSm),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${_distanceKm.toStringAsFixed(1)} km',
                                          style: AppTypography.labelSm.copyWith(color: AppColors.onSurfaceVariant),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      _roadInfo,
                                      style: AppTypography.labelSm.copyWith(
                                        color: AppColors.outline,
                                        fontSize: 10.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'On Time',
                                style: AppTypography.labelSm.copyWith(
                                  color: AppColors.onSurface,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 2. VERIFIED STUDENT DRIVER PROFILE CARD
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [BoxShadow(color: AppColors.cardShadow, blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              color: AppColors.surfaceContainerHigh,
                            ),
                            child: Center(
                              child: Text(
                                ride.driverName.substring(0, 1),
                                style: AppTypography.headlineLg.copyWith(color: AppColors.primary),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.check, size: 11, color: Colors.white),
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
                                Text(
                                  ride.driverName,
                                  style: AppTypography.headlineSm.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 17,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryFixed,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    'Verified Peer',
                                    style: AppTypography.labelSm.copyWith(
                                      color: AppColors.onPrimaryFixed,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(ride.driverDept, style: AppTypography.labelSm),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.star, size: 14, color: AppColors.ratingStar),
                                const SizedBox(width: 3),
                                Text(
                                  ride.driverRating.toStringAsFixed(2),
                                  style: AppTypography.labelSm.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.onSurface,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text('•', style: AppTypography.labelSm),
                                const SizedBox(width: 4),
                                Text(
                                  '${ride.driverRideCount} Campus Commutes',
                                  style: AppTypography.labelSm.copyWith(color: AppColors.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Quick Connect Triggers: Chat & Call
                      Row(
                        children: [
                          InkWell(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ChatScreen(
                                    rideId: ride.id,
                                    driverName: ride.driverName,
                                    vehicleModel: ride.vehicle.modelName,
                                    peerPhone: ride.driverPhone,
                                    peerRole: 'Driver',
                                  ),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: const BoxDecoration(
                                color: AppColors.surfaceContainerHigh,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.chat_bubble, color: AppColors.primary, size: 18),
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () {
                              CampusVoiceCallDialog.show(
                                context,
                                peerName: ride.driverName,
                                peerPhone: ride.driverPhone ?? '01712345678',
                                peerRole: 'Driver',
                                peerDept: ride.driverDept,
                              );
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.call, color: Colors.white, size: 18),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Trust Badges row
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildTrustBadge(Icons.school, 'DIU Registered 2021', AppColors.primary),
                        const SizedBox(width: 8),
                        _buildTrustBadge(Icons.verified_user, 'Safety Protocol Certified', AppColors.tertiary),
                        const SizedBox(width: 8),
                        _buildTrustBadge(Icons.health_and_safety, 'Fully Vaccinated', AppColors.secondary),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 3. VEHICLE DETAILS & AMENITIES
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [BoxShadow(color: AppColors.cardShadow, blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: AppColors.secondaryFixed,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.directions_car, color: AppColors.onSecondaryFixed, size: 22),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(ride.vehicle.modelName, style: AppTypography.bodyLgMedium),
                              Text(
                                '${ride.vehicle.color} • ${ride.vehicle.licensePlate}',
                                style: AppTypography.labelSm,
                              ),
                            ],
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('DIU Sticker OK', style: AppTypography.labelSm),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Feature Amenities 2x2 grid
                  Row(
                    children: [
                      Expanded(child: _buildAmenityTile(Icons.ac_unit, 'Air Conditioned')),
                      const SizedBox(width: 8),
                      Expanded(child: _buildAmenityTile(Icons.smoke_free, 'Smoke-free Car')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _buildAmenityTile(Icons.battery_charging_full, 'Phone Charger Free')),
                      const SizedBox(width: 8),
                      Expanded(child: _buildAmenityTile(Icons.luggage, 'Trunk Bag Space')),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 4. COMMUTE ITINERARY SCHEDULE TIMELINE
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [BoxShadow(color: AppColors.cardShadow, blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Commute Itinerary', style: AppTypography.headlineSm),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.secondaryFixed,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.route, size: 14, color: AppColors.onSecondaryFixed),
                            const SizedBox(width: 4),
                            Text(
                              '${ride.distanceKm} km (${ride.durationMinutes} mins)',
                              style: AppTypography.labelSm.copyWith(
                                color: AppColors.onSecondaryFixed,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Timeline Visual
                  _buildTimelineItem(
                    time: '10:30 AM',
                    title: ride.originName,
                    subtitle: ride.originSubtitle ?? 'Main Gate Passenger Pickup Canopy (DSC)',
                    isOrigin: true,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Container(
                      margin: const EdgeInsets.only(left: 20),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.alt_route, size: 14, color: AppColors.tertiary),
                          const SizedBox(width: 6),
                          Text(
                            'Ashulia Highway Corridor • Smooth Traffic',
                            style: AppTypography.labelSm.copyWith(color: AppColors.onSurface, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _buildTimelineItem(
                    time: '11:05 AM',
                    title: ride.destinationName,
                    subtitle: ride.destinationSubtitle ?? 'Exit Gate 2, Diabari (Direct Metro Link)',
                    isOrigin: false,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 5. TRANSPARENT FARE BREAKDOWN (PEER COST SHARE)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [BoxShadow(color: AppColors.cardShadow, blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Peer Cost Share', style: AppTypography.headlineSm),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primaryFixed.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Subsidized Campus Rate',
                          style: AppTypography.labelSm.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Fuel & Maintenance Split', style: AppTypography.bodyMd),
                      Text('৳${ride.farePerSeat.toInt()}.00', style: AppTypography.bodyMdMedium),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text('DIU Student Welfare Shield', style: AppTypography.bodyMd),
                          const SizedBox(width: 4),
                          const Icon(Icons.check_circle, size: 14, color: AppColors.primary),
                        ],
                      ),
                      Text(
                        'FREE (৳0)',
                        style: AppTypography.bodyMdMedium.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Total Fair Share', style: AppTypography.headlineSm),
                          Text('Pay via bKash, Nagad or Cash on arrival', style: AppTypography.labelSm),
                        ],
                      ),
                      Text(
                        '৳$totalFare',
                        style: AppTypography.display.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 6. SEAT BOOKING CONFIGURATOR & CO-PASSENGERS
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [BoxShadow(color: AppColors.cardShadow, blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Select Seats', style: AppTypography.bodyLgMedium),
                          Text('${ride.availableSeats} of ${ride.totalSeats} spots remaining', style: AppTypography.labelSm),
                        ],
                      ),
                      Row(
                        children: [
                          InkWell(
                            onTap: _seats > 1 ? () => setState(() => _seats--) : null,
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.remove, size: 16),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Text(
                              '$_seats',
                              style: AppTypography.headlineSm.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          InkWell(
                            onTap: _seats < ride.availableSeats ? () => setState(() => _seats++) : null,
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.add, size: 16, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Co-passengers on Board
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const CircleAvatar(
                              radius: 12,
                              backgroundColor: AppColors.primaryContainer,
                              child: Icon(Icons.person, size: 14, color: Colors.white),
                            ),
                            const SizedBox(width: 8),
                            Text('1 fellow DIU passenger already booked', style: AppTypography.labelSm),
                          ],
                        ),
                        const Icon(Icons.shield, color: AppColors.primary, size: 16),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Share Live Status button
                  OutlinedButton.icon(
                    onPressed: () {
                      _showToast('Live tracking link created for Guardian via WhatsApp');
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.secondary,
                      side: const BorderSide(color: AppColors.secondary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.share_location),
                    label: const Text('Share Live Trip with Guardian (WhatsApp)'),
                  ),
                  const SizedBox(height: 12),

                  // Primary Action CTA
                  ElevatedButton(
                    onPressed: () {
                      setState(() => _isReserved = true);
                      _showToast('Seat Reserved! Driver ${ride.driverName} notified.');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isReserved ? AppColors.tertiaryContainer : AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: Row(
                            children: [
                              Icon(_isReserved ? Icons.sync : Icons.verified, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                _isReserved ? 'Seat Confirmed • Awaiting Pickup' : 'Reserve Ride Seat',
                                style: AppTypography.labelLg.copyWith(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Text(
                            '৳$totalFare',
                            style: AppTypography.headlineSm.copyWith(color: AppColors.primaryFixed),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isReserved) ...[
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
                                    peerName: ride.driverName,
                                    vehicleModel: ride.vehicle.modelName,
                                    peerPhone: ride.driverPhone,
                                    peerRole: 'Driver',
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.chat_bubble_outline, size: 16),
                            label: const Text('Chat with Driver', style: TextStyle(fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: const BorderSide(color: AppColors.primary),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
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
                            icon: const Icon(Icons.call, size: 16),
                            label: const Text('Call Driver', style: TextStyle(fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2E7D32),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),

                  // Post-ride rate trigger
                  TextButton.icon(
                    onPressed: () {
                      RateRideSheet.show(
                        context: context,
                        rideId: ride.id,
                        driverName: ride.driverName,
                        onSubmit: (rating, feedback, tags) {
                          _showToast('Review submitted! Thank you for supporting peer safety.');
                        },
                      );
                    },
                    icon: const Icon(Icons.star_outline, size: 16),
                    label: const Text('Leave Ride Feedback & Rating'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrustBadge(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(text, style: AppTypography.labelSm.copyWith(color: AppColors.onSurface, fontSize: 10.5)),
        ],
      ),
    );
  }

  Widget _buildAmenityTile(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(label, style: AppTypography.labelSm.copyWith(fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildTimelineItem({
    required String time,
    required String title,
    required String subtitle,
    required bool isOrigin,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: isOrigin ? AppColors.primary : AppColors.secondary,
                shape: BoxShape.circle,
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title, style: AppTypography.bodyMdMedium.copyWith(fontWeight: FontWeight.bold)),
                  Text(
                    time,
                    style: AppTypography.labelMd.copyWith(
                      color: isOrigin ? AppColors.primary : AppColors.secondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Text(subtitle, style: AppTypography.labelSm.copyWith(color: AppColors.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
  static RideModel _defaultRide(String rideId) => RideModel(
    id: rideId,
    driverId: '',
    driverName: 'DIU Verified Driver',
    driverDept: 'DIU Student Commuter',
    driverRating: 5.0,
    driverRideCount: 1,
    originName: 'Daffodil Knowledge City',
    originSubtitle: 'Campus Main Gate (DSC)',
    originLat: 23.8769,
    originLng: 90.3204,
    destinationName: 'Destination',
    destinationSubtitle: 'Dhaka',
    destinationLat: 23.8710,
    destinationLng: 90.3800,
    departureTime: DateTime.now().add(const Duration(minutes: 15)),
    farePerSeat: 50.0,
    totalSeats: 3,
    availableSeats: 2,
    vehicle: const VehicleModel(
      id: 'v_campus',
      type: VehicleType.bike,
      modelName: 'Campus Commute Vehicle',
      color: 'Green',
      licensePlate: 'Verified DIU',
      hasAc: false,
    ),
    distanceKm: 12.0,
    durationMinutes: 25,
  );
}

class _TrackingMapPainter extends CustomPainter {
  final double driverLat;
  final double driverLng;

  _TrackingMapPainter({required this.driverLat, required this.driverLng});

  @override
  void paint(Canvas canvas, Size size) {
    // Map base
    final bgPaint = Paint()..color = const Color(0xFFE5ECE5);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Green Campus Zones
    final parkPaint = Paint()..color = const Color(0xFFD6EAD7);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(10, 10, 120, 90), const Radius.circular(16)),
      parkPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(size.width - 140, 20, 130, 110), const Radius.circular(16)),
      parkPaint,
    );

    // Birulia Lake Water
    final waterPaint = Paint()..color = const Color(0xFFCCE0FF);
    final waterPath = Path()
      ..moveTo(size.width * 0.45, 0)
      ..quadraticBezierTo(size.width * 0.55, 100, size.width * 0.48, 180)
      ..quadraticBezierTo(size.width * 0.42, 220, size.width * 0.5, size.height)
      ..lineTo(size.width * 0.6, size.height)
      ..quadraticBezierTo(size.width * 0.52, 180, size.width * 0.62, 0)
      ..close();
    canvas.drawPath(waterPath, waterPaint);

    // Birulia-Ashulia Route Polyline
    final routePaint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final routeBorderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final routePath = Path()
      ..moveTo(size.width * 0.15, size.height * 0.65)
      ..quadraticBezierTo(size.width * 0.35, size.height * 0.55, size.width * 0.5, size.height * 0.5)
      ..quadraticBezierTo(size.width * 0.7, size.height * 0.45, size.width * 0.85, size.height * 0.3);

    canvas.drawPath(routePath, routeBorderPaint);
    canvas.drawPath(routePath, routePaint);

    // Origin Pin (Gate 1)
    final originPaint = Paint()..color = AppColors.primary;
    canvas.drawCircle(Offset(size.width * 0.15, size.height * 0.65), 7, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(size.width * 0.15, size.height * 0.65), 5, originPaint);

    // Destination Pin (Uttara)
    final destPaint = Paint()..color = AppColors.secondary;
    canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.3), 7, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.3), 5, destPaint);
  }

  @override
  bool shouldRepaint(covariant _TrackingMapPainter oldDelegate) {
    return oldDelegate.driverLat != driverLat || oldDelegate.driverLng != driverLng;
  }
}
