import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/network/websocket_client.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/core/utils/gps_location_service.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/chat/presentation/screens/chat_screen.dart';
import 'package:diu_ride/features/chat/presentation/providers/chat_provider.dart';
import 'package:diu_ride/features/rating/presentation/widgets/rate_ride_sheet.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';
import 'package:diu_ride/features/rides/data/models/vehicle_model.dart';
import 'package:diu_ride/features/booking/presentation/providers/booking_provider.dart';
import 'package:diu_ride/features/booking/data/models/booking_model.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';
import 'package:diu_ride/features/safety/presentation/widgets/campus_sos_dialog.dart';
import 'package:diu_ride/core/services/notification_sound_service.dart';
import 'package:diu_ride/core/utils/direct_call_service.dart';

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
  GoogleMapController? _trackingMapController;
  bool _isMapInteractive = false;

  double _driverLat = 23.8778;
  double _driverLng = 90.3235;
  int _etaMinutes = 5;
  double _distanceKm = 1.2;
  final String _roadInfo = 'Cruising along Birulia - Ashulia Road';

  // Real-time GPS Location Sharing & Start/End Tracing
  bool _isSharingLocation = false;
  double? _mySharedLat;
  double? _mySharedLng;
  String? _mySharedMapsLink;

  double? _peerSharedLat;
  double? _peerSharedLng;
  String? _peerSharedName;
  String? _peerSharedRole;
  String? _peerSharedMapsLink;

  RideModel? _updatedRide;

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
          _trackingMapController?.animateCamera(
            CameraUpdate.newLatLng(LatLng(_driverLat, _driverLng)),
          );
        }
      } else if (msg['event'] == 'location_shared') {
        final data = msg['data'] as Map<String, dynamic>;
        if (data['rideId'] == widget.rideId && mounted) {
          final currentUserId = ref.read(authNotifierProvider).user?.id;
          final senderId = data['userId'];
          final lat = (data['latitude'] as num).toDouble();
          final lng = (data['longitude'] as num).toDouble();
          final mapsLink = data['mapsLink'] as String? ?? GpsLocationService.getGoogleMapsLocationUrl(lat, lng);
          if (senderId != currentUserId) {
            setState(() {
              _peerSharedLat = lat;
              _peerSharedLng = lng;
              _peerSharedName = data['userName'] as String? ?? 'Peer';
              _peerSharedRole = data['role'] as String? ?? 'Rider';
              _peerSharedMapsLink = mapsLink;
            });
            _showToast('${data['userName']} shared their live GPS location with Google Maps!');
          }
        }
      } else if (msg['event'] == 'ride_updated') {
        final data = msg['data'] as Map<String, dynamic>;
        if (data['id'] == widget.rideId && mounted) {
          try {
            final updated = RideModel.fromJson(data);
            setState(() {
              _updatedRide = updated;
            });
          } catch (_) {}
        }
      } else if (msg['event'] == 'ride_session_status_changed' || msg['event'] == 'ride_completed') {
        final data = msg['data'] is Map ? msg['data'] as Map<String, dynamic> : <String, dynamic>{};
        final rId = data['rideId'] ?? data['id'];
        final status = data['status']?.toString();
        if ((rId == widget.rideId || rId?.toString().contains(widget.rideId) == true) && status == 'completed' && mounted) {
          ref.invalidate(allAvailableRidesProvider);
          ref.invalidate(myBookingsProvider);
          _showToast('🏁 Trip completed and closed by rider!');
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

  Future<void> _shareMyLocation(RideModel ride) async {
    setState(() => _isSharingLocation = true);
    _showToast('Fetching device GPS coordinates...');
    final pos = await GpsLocationService.getCurrentLocation();
    final lat = pos?.latitude ?? GpsLocationService.defaultCampusLat;
    final lng = pos?.longitude ?? GpsLocationService.defaultCampusLng;
    final mapsLink = GpsLocationService.getGoogleMapsLocationUrl(lat, lng);

    final user = ref.read(authNotifierProvider).user;
    final userId = user?.id ?? 'usr_current';
    final userName = user?.name ?? 'DIU Student';
    final role = (user?.id == ride.driverId) ? 'Driver' : 'Passenger';

    await ref.read(ridesRepositoryProvider).shareLiveLocation(
      rideId: ride.id,
      userId: userId,
      userName: userName,
      role: role,
      latitude: lat,
      longitude: lng,
    );

    // Synchronize to chatbox immediately
    try {
      ref.read(chatNotifierProvider(ride.id).notifier).shareLocation(lat, lng);
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isSharingLocation = false;
        _mySharedLat = lat;
        _mySharedLng = lng;
        _mySharedMapsLink = mapsLink;
      });
      _showToast('GPS Location shared with Google Maps link!');
    }
  }

  Future<void> _startRideWithGps(RideModel ride) async {
    _showToast('Starting ride and recording GPS start point...');
    final pos = await GpsLocationService.getCurrentLocation();
    final lat = pos?.latitude ?? ride.originLat;
    final lng = pos?.longitude ?? ride.originLng;
    final mapsLink = GpsLocationService.getGoogleMapsLocationUrl(lat, lng);

    await ref.read(ridesRepositoryProvider).startRide(
      ride.id,
      startLat: lat,
      startLng: lng,
    );

    // Synchronize to chatbox immediately
    try {
      ref.read(chatNotifierProvider(ride.id).notifier).sendMessage(
        '🚀 [Trip Started] Rider has officially started the ride! Start GPS recorded: $mapsLink',
      );
    } catch (_) {}

    if (mounted) {
      _showToast('Ride Started! Start GPS & Google Maps link recorded.');
      ref.invalidate(searchRidesResultsProvider);
    }
  }

  Future<void> _completeRideWithGps(RideModel ride) async {
    _showToast('Completing ride and recording GPS end point...');
    final pos = await GpsLocationService.getCurrentLocation();
    final lat = pos?.latitude ?? ride.destinationLat;
    final lng = pos?.longitude ?? ride.destinationLng;
    final mapsLink = GpsLocationService.getGoogleMapsLocationUrl(lat, lng);

    await ref.read(ridesRepositoryProvider).completeRide(
      ride.id,
      endLat: lat,
      endLng: lng,
    );

    // Synchronize to chatbox immediately
    try {
      ref.read(chatNotifierProvider(ride.id).notifier).sendMessage(
        '🏁 [Trip Completed] Ride has arrived and completed successfully! Destination GPS recorded: $mapsLink',
      );
    } catch (_) {}

    ref.invalidate(allAvailableRidesProvider);
    ref.invalidate(allSystemRidesProvider);
    ref.invalidate(myPostedRidesProvider);
    ref.invalidate(myBookingsProvider);
    ref.invalidate(searchRidesResultsProvider);

    if (mounted) {
      _showToast('Ride Completed & Closed!');
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Color(0xFF10B981), size: 26),
              SizedBox(width: 8),
              Text('Trip Completed!'),
            ],
          ),
          content: Text(
            'Ride from ${ride.originName} to ${ride.destinationName} has been successfully completed and closed.',
            style: const TextStyle(fontSize: 13.5),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Close Screen', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final allRides = ref.watch(allAvailableRidesProvider).value ?? [];
    final RideModel ride = _updatedRide ?? (
      allRides.cast<RideModel?>().firstWhere(
        (r) => r?.id == widget.rideId,
        orElse: () => null,
      ) ?? _defaultRide(widget.rideId)
    );

    final currentUser = ref.watch(authNotifierProvider).user;
    final isDriver = currentUser != null && (
      ride.driverId == currentUser.id ||
      ride.driverId == currentUser.studentId ||
      (currentUser.phone.isNotEmpty && ride.driverPhone == currentUser.phone)
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
            const Icon(Icons.two_wheeler, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            Text('Moto Ride Details', style: AppTypography.headlineSm),
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
                height: 280,
                decoration: const BoxDecoration(
                  color: Color(0xFFE2EDE4),
                  boxShadow: [
                    BoxShadow(color: AppColors.cardShadow, blurRadius: 10, offset: Offset(0, 3)),
                  ],
                ),
                child: Stack(
                  children: [
                    // Real Interactive Google Map with live driver and route
                    GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: LatLng(_driverLat, _driverLng),
                        zoom: 14.2,
                      ),
                      onMapCreated: (ctrl) {
                        _trackingMapController = ctrl;
                      },
                      myLocationEnabled: true,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      compassEnabled: false,
                      mapToolbarEnabled: false,
                      scrollGesturesEnabled: _isMapInteractive,
                      zoomGesturesEnabled: _isMapInteractive,
                      rotateGesturesEnabled: _isMapInteractive,
                      tiltGesturesEnabled: _isMapInteractive,
                      gestureRecognizers: _isMapInteractive
                          ? {
                              Factory<OneSequenceGestureRecognizer>(
                                () => EagerGestureRecognizer(),
                              ),
                            }
                          : <Factory<OneSequenceGestureRecognizer>>{},
                      markers: _buildTrackingMarkers(ride),
                      polylines: _buildTrackingPolylines(ride),
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

                    // Top Right Action Buttons: Pan Toggle, Recenter, External Google Maps, Campus SOS
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Pan / Scroll Toggle Button
                          InkWell(
                            onTap: () => setState(() => _isMapInteractive = !_isMapInteractive),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                              decoration: BoxDecoration(
                                color: _isMapInteractive ? const Color(0xFFE65100) : Colors.white.withOpacity(0.95),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                                border: Border.all(
                                  color: _isMapInteractive ? const Color(0xFFE65100) : const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _isMapInteractive ? Icons.lock_open : Icons.pan_tool_outlined,
                                    size: 13,
                                    color: _isMapInteractive ? Colors.white : const Color(0xFF0F172A),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _isMapInteractive ? 'Pan ON' : 'Pan',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: _isMapInteractive ? Colors.white : const Color(0xFF0F172A),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Recenter Camera Button
                          InkWell(
                            onTap: () {
                              _trackingMapController?.animateCamera(
                                CameraUpdate.newLatLngZoom(
                                  LatLng(_driverLat, _driverLng),
                                  15.5,
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.95),
                                shape: BoxShape.circle,
                                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                              ),
                              child: const Icon(Icons.my_location, size: 16, color: Color(0xFFE65100)),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // External Google Maps Route Link
                          InkWell(
                            onTap: () async {
                              final url = Uri.parse(
                                'https://www.google.com/maps/dir/?api=1&origin=${ride.originLat},${ride.originLng}&destination=${ride.destinationLat},${ride.destinationLng}&travelmode=driving',
                              );
                              if (await canLaunchUrl(url)) {
                                await launchUrl(url, mode: LaunchMode.externalApplication);
                              }
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.95),
                                shape: BoxShape.circle,
                                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                              ),
                              child: const Icon(Icons.directions, size: 16, color: Color(0xFF10B981)),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Campus SOS Floating Action Shield
                          InkWell(
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
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                                  const Icon(Icons.local_police, color: Colors.white, size: 15),
                                  const SizedBox(width: 4),
                                  Text(
                                    'SOS',
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
                        ],
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

                      // Quick Connect Triggers: Chat, Ring Buzzer & Direct Call
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
                                    peerId: ride.driverId,
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
                            onTap: () => _triggerAlertRingFromTracking(ride),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF9500).withOpacity(0.14),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.notifications_active, color: Color(0xFFFF9500), size: 18),
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () {
                              DirectCallService.showCallOptions(
                                context,
                                phoneNumber: ride.driverPhone ?? '01712345678',
                                peerName: ride.driverName,
                                peerRole: 'Driver',
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
                        _buildTrustBadge(Icons.school, 'DIU Batch Verified', AppColors.primary),
                        const SizedBox(width: 8),
                        _buildTrustBadge(Icons.verified, 'Campus Commuter', AppColors.tertiary),
                        const SizedBox(width: 8),
                        _buildTrustBadge(Icons.shield_outlined, 'Safety Guaranteed', AppColors.secondary),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 3. 3D INTERACTIVE VEHICLE DETAILS & SAFETY AMENITIES CARD
            InkWell(
              onTap: () => _showVehicleSpecsAndSafetySheet(context, ride),
              borderRadius: BorderRadius.circular(24),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.white, Color(0xFFFFF7ED)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFFFD8A8), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE65100).withOpacity(0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFE65100), Color(0xFFFF9800)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFE65100).withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.two_wheeler, color: Colors.white, size: 24),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      ride.vehicle.modelName.isNotEmpty ? ride.vehicle.modelName : 'Yamaha R15 V4',
                                      style: AppTypography.bodyLgMedium.copyWith(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.info_outline, size: 14, color: Color(0xFFE65100)),
                                  ],
                                ),
                                Text(
                                  '${ride.vehicle.color} • ${ride.vehicle.licensePlate}',
                                  style: AppTypography.labelSm.copyWith(color: const Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'DIU Sticker OK',
                            style: TextStyle(
                              color: Color(0xFF16A34A),
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Motorcycle Amenities 2x2 grid with interactive touch
                    Row(
                      children: [
                        Expanded(
                          child: _buildAmenityTile(
                            Icons.sports_motorsports,
                            'Fresh Helmet Included 🪖',
                            color: const Color(0xFF10B981),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildAmenityTile(
                            Icons.verified_user,
                            'DIU Verified Bike',
                            color: const Color(0xFF0284C7),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildAmenityTile(
                            Icons.bolt,
                            'Fast Campus Transit',
                            color: const Color(0xFFF59E0B),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildAmenityTile(
                            Icons.share_location,
                            'Live GPS Sharing',
                            color: const Color(0xFF8B5CF6),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.touch_app, size: 13, color: Color(0xFFE65100)),
                          SizedBox(width: 4),
                          Text(
                            'Tap bike card to view Fresh Helmet, Safety Gear & Bike Specs',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFE65100)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // LIVE GPS LOCATION SHARING CARD (ORDER CONFIRMED / RIDER & PASSENGER)
            _buildLiveLocationSharingCard(ride),
            const SizedBox(height: 14),

            // RIDE GPS START & END TRACE + GOOGLE MAPS ROUTE CARD
            _buildGpsTraceAndRouteCard(ride),
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

            // 6. DRIVER MISSION CONTROL OR PASSENGER SEAT CONFIGURATOR
            if (isDriver)
              _buildDriverMissionControlCard(ride, ref)
            else
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
                                      peerId: ride.driverId,
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
                                DirectCallService.showCallOptions(
                                  context,
                                  phoneNumber: ride.driverPhone ?? '01712345678',
                                  peerName: ride.driverName,
                                  peerRole: 'Driver',
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

  void _confirmCancelRide(RideModel ride) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cancel Offered Ride?'),
        content: const Text('Are you sure you want to cancel this trip? Any pending requests will be cancelled.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Keep Trip')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await ref.read(ridesRepositoryProvider).cancelOfferedRide(ride.id);
              ref.invalidate(departingSoonRidesProvider);
              ref.invalidate(searchRidesResultsProvider);
              ref.invalidate(allAvailableRidesProvider);
              _showToast('Trip cancelled successfully.');
              if (mounted) Navigator.of(context).pop();
            },
            child: const Text('Cancel Trip'),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverMissionControlCard(RideModel ride, WidgetRef ref) {
    final bookingsAsync = ref.watch(rideBookingsProvider(ride.id));
    final bookings = bookingsAsync.value ?? [];

    Color statusColor;
    String statusText;
    switch (ride.status) {
      case RideStatus.published:
        statusColor = const Color(0xFFE65100);
        statusText = 'OFFERED & READY';
        break;
      case RideStatus.active:
        statusColor = const Color(0xFF2E7D32);
        statusText = 'IN PROGRESS (STARTED)';
        break;
      case RideStatus.completed:
        statusColor = const Color(0xFF00897B);
        statusText = 'COMPLETED (SAVED TO CSV)';
        break;
      case RideStatus.cancelled:
        statusColor = const Color(0xFFD32F2F);
        statusText = 'CANCELLED';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: statusColor.withOpacity(0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: statusColor.withOpacity(0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Driver Badge & Trip Status
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.sports_motorsports, color: statusColor, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Driver Mission Control',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF141416),
                        ),
                      ),
                      Text(
                        'Manage your shared trip & passengers',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withOpacity(0.5)),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Passenger Requests & Confirmation Section
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.people_alt, size: 16, color: Color(0xFFE65100)),
                        const SizedBox(width: 6),
                        Text(
                          'Passenger Bookings (${bookings.length})',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                        ),
                      ],
                    ),
                    Text(
                      '${ride.availableSeats} of ${ride.totalSeats} seats left',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280), fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                if (bookings.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Waiting for DIU peers to request seats on this trip.',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
                    ),
                  )
                else
                  ...bookings.map((b) {
                    final isPending = b.status == BookingStatus.requested;
                    final isAccepted = b.status == BookingStatus.accepted;

                    return Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isAccepted
                              ? const Color(0xFF4CAF50).withOpacity(0.5)
                              : isPending
                                  ? const Color(0xFFFF9800).withOpacity(0.5)
                                  : const Color(0xFFE0E0E0),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: const Color(0xFFE65100).withOpacity(0.12),
                                child: Text(
                                  b.passengerName.isNotEmpty ? b.passengerName[0].toUpperCase() : 'P',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFE65100)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      b.passengerName,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    Text(
                                      'Pickup: ${b.pickupPoint} • ${b.seatsBooked} seat(s) • ৳${b.totalFare.toInt()}',
                                      style: TextStyle(fontSize: 11.5, color: Colors.grey[700]),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isAccepted
                                      ? const Color(0xFFE8F5E9)
                                      : isPending
                                          ? const Color(0xFFFFF3E0)
                                          : const Color(0xFFF5F5F5),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  b.status.name.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: isAccepted
                                        ? const Color(0xFF2E7D32)
                                        : isPending
                                            ? const Color(0xFFE65100)
                                            : Colors.grey[700],
                                  ),
                                ),
                              ),
                            ],
                          ),

                          // If pending: Confirm or Decline buttons
                          if (isPending) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () async {
                                      await ref.read(bookingNotifierProvider.notifier).acceptBooking(
                                            bookingId: b.id,
                                            rideId: ride.id,
                                            driverName: ride.driverName,
                                            pickupPoint: b.pickupPoint,
                                          );
                                      ref.invalidate(rideBookingsProvider(ride.id));
                                      _showToast('Booking Confirmed for ${b.passengerName}!');
                                    },
                                    icon: const Icon(Icons.check, size: 14),
                                    label: const Text('Confirm Booking', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF2E7D32),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    await ref.read(bookingNotifierProvider.notifier).rejectBooking(
                                          bookingId: b.id,
                                          rideId: ride.id,
                                          driverName: ride.driverName,
                                        );
                                    ref.invalidate(rideBookingsProvider(ride.id));
                                    _showToast('Declined request from ${b.passengerName}.');
                                  },
                                  icon: const Icon(Icons.close, size: 14),
                                  label: const Text('Decline', style: TextStyle(fontSize: 11.5)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFFD32F2F),
                                    side: const BorderSide(color: Color(0xFFD32F2F)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  ),
                                ),
                              ],
                            ),
                          ],

                          // If accepted: Chat and Call buttons
                          if (isAccepted) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => ChatScreen(
                                          rideId: ride.id,
                                          peerName: b.passengerName,
                                          peerPhone: b.passengerPhone,
                                          peerRole: 'Passenger',
                                          peerId: b.passengerId,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.chat_bubble_outline, size: 13),
                                  label: const Text('Chat & Ring', style: TextStyle(fontSize: 11)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFFE65100),
                                    side: const BorderSide(color: Color(0xFFE65100)),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: () {
                                    DirectCallService.showCallOptions(
                                      context,
                                      phoneNumber: b.passengerPhone,
                                      peerName: b.passengerName,
                                      peerRole: 'Passenger',
                                    );
                                  },
                                  icon: const Icon(Icons.call, size: 13),
                                  label: const Text('Call', style: TextStyle(fontSize: 11)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF2E7D32),
                                    side: const BorderSide(color: Color(0xFF2E7D32)),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Primary Driver Action Buttons: GPS, Start, End, Cancel
          // 1. Share GPS
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSharingLocation ? null : () => _shareMyLocation(ride),
              icon: _isSharingLocation
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.share_location, size: 18),
              label: Text(
                _isSharingLocation ? 'Sharing GPS...' : 'Share My Live GPS with Passenger',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1976D2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // 2. Start Trip or End Trip depending on status
          if (ride.status == RideStatus.published) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _startRideWithGps(ride),
                icon: const Icon(Icons.play_arrow, size: 20),
                label: const Text(
                  'Start Trip (Record Start GPS & Time)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _confirmCancelRide(ride),
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text(
                  'Cancel Offered Ride',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFD32F2F),
                  side: const BorderSide(color: Color(0xFFD32F2F), width: 1.2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ] else if (ride.status == RideStatus.active) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _completeRideWithGps(ride),
                icon: const Icon(Icons.flag, size: 20),
                label: const Text(
                  'End Trip (Record End GPS & Auto-save CSV)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE65100),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ] else if (ride.status == RideStatus.completed) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF81C784)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, color: Color(0xFF2E7D32), size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Trip completed successfully. All rider, passenger, GPS & timing data saved to database & completed_trips.csv.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF1B5E20), fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
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

  Widget _buildAmenityTile(IconData icon, String label, {Color? color}) {
    final tileColor = color ?? AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: tileColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tileColor.withOpacity(0.2), width: 0.8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: tileColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: AppTypography.labelSm.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1E293B),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _showVehicleSpecsAndSafetySheet(BuildContext context, RideModel ride) {
    final vehicleName = ride.vehicle.modelName.isNotEmpty ? ride.vehicle.modelName : 'Yamaha R15 V4 (Campus Edition)';
    final vehicleColor = ride.vehicle.color.isNotEmpty ? ride.vehicle.color : 'Matte Blue Metallic';
    final licensePlate = ride.vehicle.licensePlate.isNotEmpty ? ride.vehicle.licensePlate : 'Dhaka Metro-HA 24-8891';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 20,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE65100), Color(0xFFFF9800)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE65100).withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.two_wheeler, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              vehicleName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0F172A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'VERIFIED',
                              style: TextStyle(
                                color: Color(0xFF10B981),
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$vehicleColor • $licensePlate',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Color(0xFFF1F5F9)),
            const SizedBox(height: 10),
            const Text(
              'Included Amenities & Safety Equipment',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 12),
            _buildSpecFeatureTile(
              icon: Icons.sports_motorsports,
              iconColor: const Color(0xFF10B981),
              title: 'Fresh & Sanitized Helmet Included 🪖',
              subtitle: 'Disinfected passenger helmet with anti-scratch visor and clean inner padding provided on every trip.',
            ),
            const SizedBox(height: 10),
            _buildSpecFeatureTile(
              icon: Icons.pan_tool_alt,
              iconColor: const Color(0xFF0284C7),
              title: 'Dual Grab Rails & Foot-pegs 🏍️',
              subtitle: 'Ergonomic pillion seating with sturdy aluminium rear grab rails for high-speed stability and comfort.',
            ),
            const SizedBox(height: 10),
            _buildSpecFeatureTile(
              icon: Icons.verified_user,
              iconColor: const Color(0xFF7C3AED),
              title: 'DIU Varsity Security Gate Sticker 🛡️',
              subtitle: 'Authorized campus sticker ensuring seamless transit past university security checkpoints without delays.',
            ),
            const SizedBox(height: 10),
            _buildSpecFeatureTile(
              icon: Icons.clean_hands,
              iconColor: const Color(0xFFE65100),
              title: 'Sanitized Commute Guarantee 🧼',
              subtitle: 'Contact points, seat, and handles sanitized before every peer journey.',
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65100),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Understood & Verified (সব ঠিক আছে)', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecFeatureTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _triggerAlertRingFromTracking(RideModel ride) async {
    final user = ref.read(authNotifierProvider).user;
    final senderName = user?.name ?? 'Commuter';
    final ringId = 'ring_${DateTime.now().millisecondsSinceEpoch}';
    final targetId = ride.driverPhone?.isNotEmpty == true
        ? ride.driverPhone!
        : (ride.driverId.isNotEmpty ? ride.driverId : ride.driverName);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFFF9500).withOpacity(0.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.notifications_active, color: Color(0xFFFF9500), size: 38),
            ),
            const SizedBox(height: 16),
            Text(
              'Ringing ${ride.driverName}...',
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
                    _showToast('Ringing stopped.');
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );

    try {
      await ref.read(ridesRepositoryProvider).triggerAlertRing(
        targetUserId: targetId,
        targetName: ride.driverName,
        senderId: user?.id ?? '',
        senderName: senderName,
        rideId: ride.id,
        ringId: ringId,
        message: '🚨 Urgent: $senderName is ringing you for pickup!',
      );
    } catch (_) {}
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
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isOrigin ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isOrigin ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                  width: 2,
                ),
              ),
              child: Center(
                child: Icon(
                  isOrigin ? Icons.my_location : Icons.location_on,
                  size: 13,
                  color: isOrigin ? const Color(0xFF10B981) : const Color(0xFFEF4444),
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title, style: AppTypography.bodyMdMedium.copyWith(fontWeight: FontWeight.bold, fontSize: 14)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: isOrigin ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      time,
                      style: TextStyle(
                        color: isOrigin ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(subtitle, style: AppTypography.labelSm.copyWith(color: AppColors.onSurfaceVariant, fontSize: 11.5)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLiveLocationSharingCard(RideModel ride) {
    return Container(
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
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primaryFixed,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.share_location, color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Live GPS Location Sharing', style: AppTypography.headlineSm),
                      Text('Google Maps link for rider & passenger', style: AppTypography.labelSm.copyWith(color: AppColors.onSurfaceVariant)),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Order Active',
                  style: AppTypography.labelSm.copyWith(
                    color: const Color(0xFF2E7D32),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Both rider (driver) and passenger can share their current GPS mobile location in real-time. Click to view on Google Maps instantly.',
            style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant, fontSize: 12.5),
          ),
          const SizedBox(height: 12),

          // Primary Share Action Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSharingLocation ? null : () => _shareMyLocation(ride),
              icon: _isSharingLocation
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.my_location, size: 18),
              label: Text(_isSharingLocation ? 'Acquiring GPS...' : 'Share My Current GPS Location'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),

          // My shared location details
          if (_mySharedLat != null && _mySharedLng != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F8F4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.pin_drop, color: AppColors.primary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Your Shared Location', style: AppTypography.labelSm.copyWith(fontWeight: FontWeight.bold, color: AppColors.primary)),
                        Text('Lat: ${_mySharedLat!.toStringAsFixed(5)}, Lng: ${_mySharedLng!.toStringAsFixed(5)}', style: AppTypography.labelSm),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      if (_mySharedMapsLink != null) {
                        GpsLocationService.openGoogleMaps(_mySharedMapsLink!);
                      }
                    },
                    icon: const Icon(Icons.open_in_new, size: 14),
                    label: const Text('Google Maps', style: TextStyle(fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Peer shared location details
          if (_peerSharedLat != null && _peerSharedLng != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEBF3FB),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF1976D2).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_pin_circle, color: Color(0xFF1976D2), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_peerSharedName ?? "Peer"} (${_peerSharedRole ?? "Rider"}) Location',
                          style: AppTypography.labelSm.copyWith(fontWeight: FontWeight.bold, color: const Color(0xFF1976D2)),
                        ),
                        Text('Lat: ${_peerSharedLat!.toStringAsFixed(5)}, Lng: ${_peerSharedLng!.toStringAsFixed(5)}', style: AppTypography.labelSm),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      if (_peerSharedMapsLink != null) {
                        GpsLocationService.openGoogleMaps(_peerSharedMapsLink!);
                      }
                    },
                    icon: const Icon(Icons.map, size: 14),
                    label: const Text('View Maps', style: TextStyle(fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1976D2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGpsTraceAndRouteCard(RideModel ride) {
    return Container(
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
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.secondaryFixed,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.alt_route, color: AppColors.onSecondaryFixed, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ride GPS Route & Tracing', style: AppTypography.headlineSm),
                      Text('Recorded start point, end point & route', style: AppTypography.labelSm.copyWith(color: AppColors.onSurfaceVariant)),
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
                  ride.status.name.toUpperCase(),
                  style: AppTypography.labelSm.copyWith(fontWeight: FontWeight.bold, fontSize: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Start Point GPS Trace
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: Color(0xFF2E7D32),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Start Point Trace', style: AppTypography.bodyMdMedium.copyWith(fontWeight: FontWeight.bold)),
                      if (ride.startLat != null && ride.startLng != null) ...[
                        Text(
                          'GPS: ${ride.startLat!.toStringAsFixed(5)}, ${ride.startLng!.toStringAsFixed(5)}',
                          style: AppTypography.labelSm.copyWith(color: AppColors.onSurfaceVariant),
                        ),
                        if (ride.startTime != null)
                          Text(
                            'Started: ${ride.startTime!.toLocal().toString().split('.')[0]}',
                            style: AppTypography.labelSm.copyWith(color: AppColors.outline, fontSize: 10),
                          ),
                      ] else ...[
                        Text('Origin: ${ride.originName}', style: AppTypography.labelSm.copyWith(color: AppColors.onSurfaceVariant)),
                        Text('GPS: ${ride.originLat.toStringAsFixed(4)}, ${ride.originLng.toStringAsFixed(4)}', style: AppTypography.labelSm.copyWith(color: AppColors.outline, fontSize: 10)),
                      ],
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    final url = ride.googleMapsStartUrl;
                    GpsLocationService.openGoogleMaps(url);
                  },
                  icon: const Icon(Icons.map, size: 14),
                  label: const Text('Maps', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2E7D32),
                    side: const BorderSide(color: Color(0xFF2E7D32)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // End Point GPS Trace
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE65100),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.flag, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('End Point Trace', style: AppTypography.bodyMdMedium.copyWith(fontWeight: FontWeight.bold)),
                      if (ride.endLat != null && ride.endLng != null) ...[
                        Text(
                          'GPS: ${ride.endLat!.toStringAsFixed(5)}, ${ride.endLng!.toStringAsFixed(5)}',
                          style: AppTypography.labelSm.copyWith(color: AppColors.onSurfaceVariant),
                        ),
                        if (ride.endTime != null)
                          Text(
                            'Completed: ${ride.endTime!.toLocal().toString().split('.')[0]}',
                            style: AppTypography.labelSm.copyWith(color: AppColors.outline, fontSize: 10),
                          ),
                      ] else ...[
                        Text('Destination: ${ride.destinationName}', style: AppTypography.labelSm.copyWith(color: AppColors.onSurfaceVariant)),
                        Text('GPS: ${ride.destinationLat.toStringAsFixed(4)}, ${ride.destinationLng.toStringAsFixed(4)}', style: AppTypography.labelSm.copyWith(color: AppColors.outline, fontSize: 10)),
                      ],
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    final url = ride.googleMapsEndUrl;
                    GpsLocationService.openGoogleMaps(url);
                  },
                  icon: const Icon(Icons.map, size: 14),
                  label: const Text('Maps', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFE65100),
                    side: const BorderSide(color: Color(0xFFE65100)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Complete Driving Route on Google Maps
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                GpsLocationService.openGoogleMaps(ride.googleMapsRouteUrl);
              },
              icon: const Icon(Icons.navigation, size: 18),
              label: const Text('Open Complete Route in Google Maps'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),

          // Driver Trip Management Buttons (Start Ride / Complete Ride)
          const SizedBox(height: 10),
          Row(
            children: [
              if (ride.status == RideStatus.published)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _startRideWithGps(ride),
                    icon: const Icon(Icons.play_circle_outline, size: 16),
                    label: const Text('Start Ride (GPS)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              if (ride.status == RideStatus.active)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _completeRideWithGps(ride),
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('Complete Ride (GPS)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65100),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
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

  Set<Marker> _buildTrackingMarkers(RideModel ride) {
    final markers = <Marker>{};

    // Driver live position
    markers.add(
      Marker(
        markerId: const MarkerId('driver_live'),
        position: LatLng(_driverLat, _driverLng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: InfoWindow(
          title: '🏍️ ${ride.driverName} (Live Biker)',
          snippet: 'ETA: $_etaMinutes mins away • ${_distanceKm.toStringAsFixed(1)} km',
        ),
      ),
    );

    // Origin
    markers.add(
      Marker(
        markerId: const MarkerId('origin_pin'),
        position: LatLng(ride.originLat, ride.originLng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(
          title: '🟢 Pickup: ${ride.originName}',
        ),
      ),
    );

    // Destination
    markers.add(
      Marker(
        markerId: const MarkerId('destination_pin'),
        position: LatLng(ride.destinationLat, ride.destinationLng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
          title: '🏁 Destination: ${ride.destinationName}',
        ),
      ),
    );

    // Peer shared GPS if any
    if (_peerSharedLat != null && _peerSharedLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('peer_shared_gps'),
          position: LatLng(_peerSharedLat!, _peerSharedLng!),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(
            title: '📍 ${_peerSharedName ?? "Peer"} (Live GPS)',
            snippet: _peerSharedRole ?? 'Passenger',
          ),
        ),
      );
    }

    // My shared GPS if any
    if (_mySharedLat != null && _mySharedLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('my_shared_gps'),
          position: LatLng(_mySharedLat!, _mySharedLng!),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
          infoWindow: const InfoWindow(
            title: '👤 My Live GPS',
          ),
        ),
      );
    }

    return markers;
  }

  Set<Polyline> _buildTrackingPolylines(RideModel ride) {
    return {
      Polyline(
        polylineId: const PolylineId('ride_active_route'),
        points: [
          LatLng(ride.originLat, ride.originLng),
          LatLng(_driverLat, _driverLng),
          LatLng(ride.destinationLat, ride.destinationLng),
        ],
        color: const Color(0xFFE65100),
        width: 5,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ),
    };
  }
}
