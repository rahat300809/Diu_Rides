import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    final departingRidesAsync = ref.watch(departingSoonRidesStreamProvider);
    final allRidesAsync = ref.watch(allAvailableRidesProvider);
    final List<RideModel> allRides = allRidesAsync.value ?? [];

    // Filter matching rides if searching
    final trimmedQuery = _activeSearchQuery.trim().toLowerCase();
    final List<RideModel> matchingBikes = trimmedQuery.isEmpty
        ? []
        : allRides.where((r) {
            final isBike = r.vehicle.type == VehicleType.bike;
            if (!isBike) return false;

            final destMatch = r.destinationName.toLowerCase().contains(trimmedQuery) ||
                (r.destinationSubtitle?.toLowerCase().contains(trimmedQuery) ?? false);
            final originMatch = r.originName.toLowerCase().contains(trimmedQuery) ||
                (r.originSubtitle?.toLowerCase().contains(trimmedQuery) ?? false);
            final corridorMatch = r.routeCorridor.toLowerCase().contains(trimmedQuery);

            return destMatch || originMatch || corridorMatch;
          }).toList();

    // Check if user has an active ride (either as driver or recent ride)
    final activeRide = allRides.cast<RideModel?>().firstWhere(
          (r) => r?.status == RideStatus.active,
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
                            Container(
                              padding: const EdgeInsets.all(2.5),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: CircleAvatar(
                                radius: 21,
                                backgroundColor: const Color(0xFF141416),
                                child: Text(
                                  user?.name.isNotEmpty == true
                                      ? user!.name[0].toUpperCase()
                                      : 'S',
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
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
                                const Row(
                                  children: [
                                    Text(
                                      'DIU Smart City, Ashulia',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                    ),
                                    SizedBox(width: 3),
                                    Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.white),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),

                        // Notification Glass Bell & Active Ride Status Pill
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

                            // Translucent Glass Notification Bell Button (Matching Reference 2)
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.24),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white.withOpacity(0.35)),
                              ),
                              child: const Icon(Icons.notifications_none, size: 20, color: Colors.white),
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
                      'Explore Campus Comfortably',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: Colors.white.withOpacity(0.92),
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    const SizedBox(height: 16),

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

              // 4. "Choose Your Ride" Segmented Dual-Pill Card (Directly Matching Reference 2)
              Container(
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
              ),

              // 5. Clean Moto Service Categories (4-Grid Apple Style)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Campus Moto Share',
                      style: AppTypography.headlineSm.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF141416),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => widget.onNavigateTab(1),
                      child: const Text(
                        'See All',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFE65100),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _buildServiceCard(
                      icon: Icons.two_wheeler,
                      title: 'Standard Moto',
                      subtitle: '1 seat • Avg ৳35',
                      tag: 'Fastest',
                      tagColor: const Color(0xFF2E7D32),
                      onTap: () => widget.onNavigateTab(1),
                    ),
                    const SizedBox(width: 10),
                    _buildServiceCard(
                      icon: Icons.sports_motorsports,
                      title: 'Helmet Ready',
                      subtitle: 'Clean helmet provided',
                      tag: 'Helmet',
                      tagColor: const Color(0xFFE65100),
                      onTap: () => widget.onNavigateTab(1),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _buildServiceCard(
                      icon: Icons.female,
                      title: 'Female Moto',
                      subtitle: 'Female peer commute',
                      tag: 'Reserved',
                      tagColor: const Color(0xFFE91E63),
                      onTap: () {
                        ref.read(rideSearchFilterProvider.notifier).toggleFemaleOnly();
                        widget.onNavigateTab(1);
                      },
                    ),
                    const SizedBox(width: 10),
                    _buildServiceCard(
                      icon: Icons.flash_on,
                      title: 'Metro Express',
                      subtitle: 'Diabari corridor link',
                      tag: 'Express',
                      tagColor: const Color(0xFFFF9500),
                      onTap: () => widget.onNavigateTab(1),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 6. Live Departing Peer Motorbikes Carousel (Realtime Synced)
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

  Widget _buildServiceCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String tag,
    required Color tagColor,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.black.withOpacity(0.06)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: tagColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 18, color: tagColor),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: tagColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      tag,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: tagColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
