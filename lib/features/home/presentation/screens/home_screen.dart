import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/booking/presentation/widgets/booking_confirmation_sheet.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';
import 'package:diu_ride/features/rides/data/models/vehicle_model.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';
import 'package:diu_ride/features/rides/presentation/widgets/post_ride_request_sheet.dart';
import 'package:diu_ride/features/home/presentation/widgets/apple_ios_destination_search.dart';
import 'package:diu_ride/features/home/presentation/widgets/destination_matching_bikes_view.dart';
import 'package:diu_ride/features/home/presentation/widgets/departing_rides_carousel.dart';
import 'package:diu_ride/features/tracking/presentation/screens/ride_details_tracking_screen.dart';
import 'package:diu_ride/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:diu_ride/features/notifications/presentation/providers/notifications_provider.dart';
import 'package:diu_ride/features/chat/presentation/screens/campus_messages_screen.dart';
import 'package:diu_ride/features/profile/presentation/screens/profile_screen.dart';
import 'package:diu_ride/features/home/presentation/widgets/live_ride_status_card.dart';
import 'package:diu_ride/core/constants/campus_locations.dart';
import 'package:diu_ride/core/providers/app_mode_provider.dart';
import 'package:diu_ride/features/home/presentation/widgets/app_mode_toggle_bar.dart';
import 'package:diu_ride/features/home/presentation/widgets/rider_student_requests_section.dart';

class HomeScreen extends ConsumerStatefulWidget {
  final Function(int tabIndex) onNavigateTab;
  final Function(String query) onSearchQuery;

  const HomeScreen({
    super.key,
    required this.onNavigateTab,
    required this.onSearchQuery,
  });

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _activeSearchQuery = '';
  String _currentLocation = 'DIU Smart City, Ashulia';
  Uint8List? _profilePhotoBytes;

  @override
  void initState() {
    super.initState();
    _loadProfilePhoto();
  }

  Future<void> _loadProfilePhoto() async {
    final prefs = await SharedPreferences.getInstance();
    final b64 = prefs.getString('profile_photo_b64');
    if (b64 != null && b64.isNotEmpty) {
      try {
        if (mounted) {
          setState(() => _profilePhotoBytes = base64Decode(b64));
        }
      } catch (_) {}
    }
  }

  void _showLocationPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Select Campus Pickup Location',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose your current boarding spot on DIU Campus',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            ...CampusLocations.allCampusSpots.map((spot) => ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.place, color: Color(0xFFE65100), size: 20),
              ),
              title: Text(spot.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: Text(spot.subtitle, style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
              trailing: _currentLocation == spot.name
                  ? const Icon(Icons.check_circle, color: Color(0xFFE65100))
                  : null,
              onTap: () {
                setState(() => _currentLocation = spot.name);
                Navigator.pop(ctx);
                _showToast('Location Updated', 'Pickup set to ${spot.name}');
              },
            )),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showToast(String title, String subtitle) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1C1C1E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        duration: const Duration(seconds: 4),
        content: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFE65100), Color(0xFFF57C00)],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.two_wheeler, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.labelLg.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: AppTypography.labelSm.copyWith(
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleRequestSeat(RideModel ride) {
    BookingConfirmationSheet.show(
      context: context,
      ride: ride,
      onBookingSuccess: () {
        _showToast(
          'Moto Seat Requested!',
          'Booking sent to ${ride.driverName} • Fare: ৳${ride.farePerSeat.toInt()} (1 seat)',
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authNotifierProvider).user;
    final appMode = ref.watch(appModeProvider);
    final departingRidesAsync = ref.watch(departingSoonRidesStreamProvider);
    final allRidesAsync = ref.watch(allAvailableRidesProvider);
    final List<RideModel> allRides = allRidesAsync.value ?? [];

    final unreadNotificationCount = ref.watch(unreadNotificationCountProvider);

    // Filter matching rides if searching (supports AB4, both From & To)
    final trimmedQuery = _activeSearchQuery.trim().toLowerCase();
    final isAb4Query = trimmedQuery.contains('ab4') || trimmedQuery.contains('ab 4') || trimmedQuery.contains('ab-4');
    final List<RideModel> matchingBikes = trimmedQuery.isEmpty
        ? []
        : allRides.where((r) {
            // Do not show user's own offered ride in search results to book!
            if (user != null && (r.driverId == user.id || r.driverId == user.studentId || (user.phone.isNotEmpty && r.driverPhone == user.phone))) {
              return false;
            }
            final destMatch = r.destinationName.toLowerCase().contains(trimmedQuery) ||
                (r.destinationSubtitle?.toLowerCase().contains(trimmedQuery) ?? false);
            final originMatch = r.originName.toLowerCase().contains(trimmedQuery) ||
                (r.originSubtitle?.toLowerCase().contains(trimmedQuery) ?? false);
            final corridorMatch = r.routeCorridor.toLowerCase().contains(trimmedQuery);
            final driverMatch = r.driverName.toLowerCase().contains(trimmedQuery);

            final ab4Match = isAb4Query && (
              r.originName.toLowerCase().contains('academic building 4') ||
              r.destinationName.toLowerCase().contains('academic building 4') ||
              r.originName.toLowerCase().contains('ab4') ||
              r.destinationName.toLowerCase().contains('ab4')
            );

            return destMatch || originMatch || corridorMatch || driverMatch || ab4Match;
          }).toList();

    // Check if user has an active ride as driver
    final systemRides = ref.watch(allSystemRidesProvider).value ?? [];
    final activeRide = systemRides.cast<RideModel?>().firstWhere(
          (r) => r?.status == RideStatus.active &&
                 user != null &&
                 (r?.driverId == user.id || r?.driverId == user.studentId || (user.phone.isNotEmpty && r?.driverPhone == user.phone)),
          orElse: () => null,
        );

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: RefreshIndicator(
        color: const Color(0xFFE65100),
        onRefresh: () async {
          ref.invalidate(departingSoonRidesStreamProvider);
          ref.invalidate(departingSoonRidesProvider);
          ref.invalidate(allAvailableRidesProvider);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.only(bottom: 30),
          child: Column(
            children: [
              // 1. Radiant Sunset Amber Header (Directly Matching Reference Images)
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                      Color(0xFFE65100), // Rich Sunset Amber
                      Color(0xFFF57C00), // Vibrant Orange
                      Color(0xFFFFB74D), // Golden Peach Glow
                    ],
                  ),
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x28E65100),
                      blurRadius: 20,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                padding: EdgeInsets.fromLTRB(
                  20,
                  MediaQuery.of(context).padding.top + 10,
                  20,
                  22,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Row: User Avatar, Current Location & Glass Action Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                                ).then((_) => _loadProfilePhoto());
                              },
                              child: Container(
                                padding: const EdgeInsets.all(2.5),
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: CircleAvatar(
                                  radius: 21,
                                  backgroundColor: const Color(0xFF141416),
                                  backgroundImage: _profilePhotoBytes != null
                                      ? MemoryImage(_profilePhotoBytes!)
                                      : null,
                                  child: _profilePhotoBytes == null
                                      ? Text(
                                          user?.name.isNotEmpty == true
                                              ? user!.name[0].toUpperCase()
                                              : 'S',
                                          style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: _showLocationPicker,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Current Location',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white.withOpacity(0.85),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(maxWidth: 160),
                                        child: Text(
                                          _currentLocation,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 3),
                                      const Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.white),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        // Notification Glass Bell, Messages & Active Ride Status Pill
                        Row(
                          children: [
                            if (activeRide != null)
                              GestureDetector(
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => RideDetailsTrackingScreen(rideId: activeRide.id),
                                    ),
                                  );
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  margin: const EdgeInsets.only(right: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.12),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.two_wheeler, size: 14, color: Color(0xFFE65100)),
                                      SizedBox(width: 5),
                                      Text(
                                        'Active Ride',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFFE65100),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            // Messages Button
                            GestureDetector(
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => CampusMessagesScreen(
                                      onExploreRides: () {
                                        Navigator.of(context).pop();
                                        widget.onNavigateTab(1);
                                      },
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                width: 38,
                                height: 38,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.24),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white.withOpacity(0.35)),
                                ),
                                child: const Icon(Icons.chat_bubble_outline, size: 19, color: Colors.white),
                              ),
                            ),

                            // Translucent Glass Notification Bell Button with badge
                            GestureDetector(
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                                );
                              },
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.24),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white.withOpacity(0.35)),
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    const Icon(Icons.notifications_none, size: 20, color: Colors.white),
                                    if (unreadNotificationCount > 0)
                                      Positioned(
                                        top: 6,
                                        right: 6,
                                        child: Container(
                                          width: 9,
                                          height: 9,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFFF3B30),
                                            shape: BoxShape.circle,
                                          ),
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

                    const SizedBox(height: 18),

                    // Greeting Headline on Sunset Gradient
                    Text(
                      'Hello, ${user?.name.split(" ").first ?? "Student"}',
                      style: const TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      appMode.isPassenger
                          ? 'Passenger Mode • Find rides & request seats'
                          : (appMode.isRider
                              ? 'Rider Mode • Ready to offer rides & pick up peers'
                              : 'Explore Campus Comfortably'),
                      style: TextStyle(
                        fontSize: 13.5,
                        color: Colors.white.withOpacity(0.92),
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    // Modern Segmented Mode Toggle Bar (All | Passenger | Rider)
                    AppModeToggleBar(
                      onModeChanged: (_) => setState(() {}),
                    ),

                    const SizedBox(height: 6),

                    // 2. Apple iOS 3D Floating Destination Search Bar
                    AppleIosDestinationSearch(
                      allRides: allRides,
                      currentQuery: _activeSearchQuery,
                      onQueryChanged: (query) {
                        setState(() {
                          _activeSearchQuery = query;
                        });
                      },
                      onDestinationSelected: (destination) {
                        setState(() {
                          _activeSearchQuery = destination;
                        });
                        _showToast(
                          'Checking bikes to $destination...',
                          'Scanning peers heading in this direction',
                        );
                      },
                      onClear: () {
                        setState(() {
                          _activeSearchQuery = '';
                        });
                      },
                    ),
                  ],
                ),
              ),

              // Live Ride & Commute Status Card (Instant visibility and quick access)
              LiveRideStatusCard(
                onNavigateTab: widget.onNavigateTab,
              ),

              // 3. Live Destination Bike Matching Results View (When typing e.g. "Uttara")
              if (trimmedQuery.isNotEmpty)
                DestinationMatchingBikesView(
                  query: _activeSearchQuery,
                  matchingRides: matchingBikes,
                  onRequestSeat: _handleRequestSeat,
                  onClearQuery: () {
                    setState(() {
                      _activeSearchQuery = '';
                    });
                  },
                  onSetAsDefault: (address) async {
                    await ref
                        .read(authNotifierProvider.notifier)
                        .updateDefaultAddress(address);
                    _showToast(
                      'Default Address Saved!',
                      'You will get early alerts whenever a peer leaves for $address',
                    );
                  },
                ),

              // 4. "Choose Your Ride" Segmented Dual-Pill Card (Adaptive to AppMode)
              _buildChooseRideCard(appMode),

              const SizedBox(height: 12),

              // 5. Rider Student Pickup Requests (Shown in Rider & All Modes)
              if (appMode.showRiderFeatures)
                RiderStudentRequestsSection(
                  onSeeAll: () => widget.onNavigateTab(1),
                ),

              if (appMode.showRiderFeatures && appMode.showPassengerFeatures)
                const SizedBox(height: 16),

              // 6. Live Departing Peer Motorbikes Carousel (Shown in Passenger & All Modes)
              if (appMode.showPassengerFeatures || appMode.isAll)
                departingRidesAsync.when(
                  data: (rides) {
                    final bikeRides = rides.where((r) => r.vehicle.type == VehicleType.bike).toList();
                    return DepartingRidesCarousel(
                      rides: bikeRides.isNotEmpty ? bikeRides : rides,
                      onRequestSeat: _handleRequestSeat,
                      onSeeAll: () {
                        widget.onNavigateTab(1);
                      },
                    );
                  },
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: CircularProgressIndicator(color: Color(0xFFE65100)),
                    ),
                  ),
                  error: (err, _) => Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text('Failed to load rides: $err', style: AppTypography.bodyMd),
                  ),
                ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChooseRideCard(AppMode appMode) {
    if (appMode.isRider) {
      return Container(
        margin: const EdgeInsets.fromLTRB(20, 16, 20, 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFF0F0F2)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0C000000),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rider & Biker Hub',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF141416),
                        letterSpacing: -0.3,
                      ),
                    ),
                    SizedBox(height: 1),
                    Text(
                      'Offer Rides & Pick Up Peers',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF8E8E93),
                        fontWeight: FontWeight.w500,
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
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.two_wheeler, size: 14, color: Color(0xFFE65100)),
                      SizedBox(width: 4),
                      Text(
                        'Rider Mode',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFE65100),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                // Left: Offer Ride (Radiant Sunset Amber Gradient)
                Expanded(
                  child: InkWell(
                    onTap: () => widget.onNavigateTab(2),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFE65100), Color(0xFFF57C00)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFE65100).withOpacity(0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Offer Ride',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                              ),
                              Icon(Icons.add_circle_outline, size: 20, color: Colors.white),
                            ],
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Publish bike route & seats',
                            style: TextStyle(fontSize: 11, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Right: Student Requests (Pitch obsidian black)
                Expanded(
                  child: InkWell(
                    onTap: () => widget.onNavigateTab(1),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141416),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Pickup Requests',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                              ),
                              Icon(Icons.hail_rounded, size: 17, color: Color(0xFFFFA000)),
                            ],
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Peers needing a ride',
                            style: TextStyle(fontSize: 11, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (appMode.isPassenger) {
      return Container(
        margin: const EdgeInsets.fromLTRB(20, 16, 20, 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFF0F0F2)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0C000000),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Choose Your Ride',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF141416),
                        letterSpacing: -0.3,
                      ),
                    ),
                    SizedBox(height: 1),
                    Text(
                      'Campus Peer Commute Booking',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF8E8E93),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.hail_rounded, size: 14, color: Color(0xFF2E7D32)),
                      SizedBox(width: 4),
                      Text(
                        'Passenger Mode',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2E7D32),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                // Left: Find Ride (White pill with subtle border)
                Expanded(
                  child: InkWell(
                    onTap: () => widget.onNavigateTab(1),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F9FA),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Find Ride',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: Color(0xFF141416),
                                ),
                              ),
                              Icon(Icons.explore_outlined, size: 20, color: Color(0xFFE65100)),
                            ],
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Bikes arrive in 3-5m',
                            style: TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Right: Request / Schedule (Pitch obsidian black)
                Expanded(
                  child: InkWell(
                    onTap: () => PostRideRequestSheet.show(context),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141416),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Request Ride',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                              ),
                              Icon(Icons.calendar_today, size: 17, color: Color(0xFFFFA000)),
                            ],
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Book / Throw request',
                            style: TextStyle(fontSize: 11, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Default / All Mode
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF0F0F2)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Choose Your Ride',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF141416),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 1),
          const Text(
            'Campus Peer Commute',
            style: TextStyle(
              fontSize: 11.5,
              color: Color(0xFF8E8E93),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              // Left: Ride (White pill with subtle border)
              Expanded(
                child: InkWell(
                  onTap: () => widget.onNavigateTab(1),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Ride',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: Color(0xFF141416),
                              ),
                            ),
                            Icon(Icons.two_wheeler, size: 20, color: Color(0xFFE65100)),
                          ],
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Bikes arrive in 3-5m',
                          style: TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Right: Schedule / Request (Pitch obsidian black pill matching reference 2!)
              Expanded(
                child: InkWell(
                  onTap: () => PostRideRequestSheet.show(context),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141416),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Schedule',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: Colors.white,
                              ),
                            ),
                            Icon(Icons.calendar_today, size: 17, color: Color(0xFFFFA000)),
                          ],
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Book / Throw request',
                          style: TextStyle(fontSize: 11, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

