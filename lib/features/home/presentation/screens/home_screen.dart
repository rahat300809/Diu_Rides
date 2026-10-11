import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/booking/presentation/widgets/booking_confirmation_sheet.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';
import 'package:diu_ride/features/rides/data/models/vehicle_model.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';
import 'package:diu_ride/features/home/presentation/widgets/apple_ios_destination_search.dart';
import 'package:diu_ride/features/home/presentation/widgets/campus_category_grid.dart';
import 'package:diu_ride/features/home/presentation/widgets/campus_security_strip.dart';
import 'package:diu_ride/features/home/presentation/widgets/default_commute_address_card.dart';
import 'package:diu_ride/features/home/presentation/widgets/departing_rides_carousel.dart';
import 'package:diu_ride/features/home/presentation/widgets/destination_matching_bikes_view.dart';

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
  VehicleType? _selectedCategory = VehicleType.bike; // Default to Bikes Only
  bool _femaleOnlyCategory = false;
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
                  colors: [Color(0xFF007AFF), Color(0xFF0051B3)],
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

  void _onCategorySelected(VehicleType? type, bool isFemaleOnly) {
    setState(() {
      if (isFemaleOnly) {
        _femaleOnlyCategory = !_femaleOnlyCategory;
        _selectedCategory = VehicleType.bike;
      } else {
        _selectedCategory = VehicleType.bike;
        _femaleOnlyCategory = false;
      }
    });

    ref.read(rideSearchFilterProvider.notifier).toggleVehicleType(VehicleType.bike);
    if (_femaleOnlyCategory) {
      ref.read(rideSearchFilterProvider.notifier).toggleFemaleOnly();
    }
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

    // Get all available rides for destination search matching
    final List<RideModel> allRides = allRidesAsync.value ?? [];

    // Filter matching rides if user is searching for a destination (e.g. Uttara)
    final trimmedQuery = _activeSearchQuery.trim().toLowerCase();
    final List<RideModel> matchingBikes = trimmedQuery.isEmpty
        ? []
        : allRides.where((r) {
            // Strictly bikes only
            final isBike = r.vehicle.type == VehicleType.bike;
            if (!isBike) return false;

            final destMatch = r.destinationName.toLowerCase().contains(trimmedQuery) ||
                (r.destinationSubtitle?.toLowerCase().contains(trimmedQuery) ?? false);
            final originMatch = r.originName.toLowerCase().contains(trimmedQuery) ||
                (r.originSubtitle?.toLowerCase().contains(trimmedQuery) ?? false);
            final corridorMatch = r.routeCorridor.toLowerCase().contains(trimmedQuery);

            return destMatch || originMatch || corridorMatch;
          }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: RefreshIndicator(
        color: const Color(0xFF007AFF),
        onRefresh: () async {
          ref.invalidate(departingSoonRidesStreamProvider);
          ref.invalidate(departingSoonRidesProvider);
          ref.invalidate(allAvailableRidesProvider);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.only(bottom: 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Apple iOS 3D Header: Greeting & Status Strip
              Padding(
                padding: const EdgeInsets.only(left: 20, right: 20, top: 12, bottom: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hi, ${user?.name ?? "DIU Student"}',
                          style: AppTypography.headlineSm.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF1C1C1E),
                            letterSpacing: -0.5,
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: Color(0xFF00C853),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '${user?.department ?? "DIU"} • ${user?.batch ?? "Campus Member"}',
                              style: AppTypography.labelSm.copyWith(
                                color: const Color(0xFF8E8E93),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    // Moto Badge Pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.black.withOpacity(0.06)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.two_wheeler, size: 16, color: Color(0xFF007AFF)),
                          SizedBox(width: 5),
                          Text(
                            'Bikes Only',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF007AFF),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 2. Campus Security & Location Strip
              CampusSecurityStrip(
                onTapLocation: () {
                  _showToast('Location Refreshed', 'GPS Coordinates locked to DIU Smart City');
                },
              ),

              // 3. Apple iOS 3D Top Destination Search Bar (With Real-Time Auto-Suggestions)
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

              // 4. Live Destination Bike Matching Results View (e.g. When searching "Uttara")
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

              // 5. Default Commute Address Card (Early Notification Base)
              DefaultCommuteAddressCard(
                onAddressSelectedForSearch: (address) {
                  setState(() {
                    _activeSearchQuery = address;
                  });
                },
              ),

              // 6. Campus Moto Categories (Bikes Only: Standard Moto, Helmet Ready, Female Moto, Express Metro)
              CampusCategoryGrid(
                selectedType: _selectedCategory,
                femaleOnlySelected: _femaleOnlyCategory,
                onSelectCategory: _onCategorySelected,
              ),

              // (Map visualization removed from landing page as requested!)

              // 7. Live Departing Peer Motorbikes Carousel (Realtime Synced)
              departingRidesAsync.when(
                data: (rides) {
                  // Filter strictly to bikes
                  final bikeRides = rides.where((r) => r.vehicle.type == VehicleType.bike).toList();
                  return DepartingRidesCarousel(
                    rides: bikeRides.isNotEmpty ? bikeRides : rides,
                    onRequestSeat: _handleRequestSeat,
                    onSeeAll: () {
                      ref.read(rideSearchFilterProvider.notifier).setAllRidesMode(true);
                      ref.read(rideSearchFilterProvider.notifier).clearFilters();
                      widget.onNavigateTab(1);
                    },
                  );
                },
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: CircularProgressIndicator(color: Color(0xFF007AFF)),
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
}
