import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/features/booking/presentation/widgets/booking_confirmation_sheet.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';
import 'package:diu_ride/features/rides/data/models/vehicle_model.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';
import 'package:diu_ride/features/safety/presentation/widgets/campus_sos_dialog.dart';
import 'package:diu_ride/features/home/presentation/widgets/campus_category_grid.dart';
import 'package:diu_ride/features/home/presentation/widgets/campus_security_strip.dart';
import 'package:diu_ride/features/home/presentation/widgets/community_trust_sos_card.dart';
import 'package:diu_ride/features/home/presentation/widgets/departing_rides_carousel.dart';
import 'package:diu_ride/features/home/presentation/widgets/destination_search_card.dart';
import 'package:diu_ride/features/home/presentation/widgets/interactive_map_preview.dart';
import 'package:diu_ride/features/webview/presentation/screens/campus_webview_screen.dart';

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
  VehicleType? _selectedCategory;
  bool _femaleOnlyCategory = false;

  void _showToast(String title, String subtitle) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.inverseSurface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        duration: const Duration(seconds: 4),
        content: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: AppColors.primaryFixed,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, size: 18, color: AppColors.onPrimaryFixed),
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
                      color: AppColors.inverseOnSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: AppTypography.labelSm.copyWith(
                      color: AppColors.inverseOnSurface.withOpacity(0.8),
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
        _selectedCategory = null;
      } else {
        _selectedCategory = (_selectedCategory == type) ? null : type;
        _femaleOnlyCategory = false;
      }
    });

    if (_selectedCategory != null) {
      ref.read(rideSearchFilterProvider.notifier).toggleVehicleType(_selectedCategory!);
      widget.onNavigateTab(1); // Jump to search
    } else if (_femaleOnlyCategory) {
      ref.read(rideSearchFilterProvider.notifier).toggleFemaleOnly();
      widget.onNavigateTab(1);
    }
  }

  void _handlePinTap(String driverName, String rideType) {
    _showToast(
      '$driverName selected',
      'Route: Ashulia Corridor • $rideType active on map',
    );
  }

  void _handleRequestSeat(RideModel ride) {
    BookingConfirmationSheet.show(
      context: context,
      ride: ride,
      onBookingSuccess: () {
        _showToast(
          'Request Sent to ${ride.driverName}!',
          'Fare: ৳${ride.farePerSeat.toInt()} • Awaiting driver confirmation',
        );
      },
    );
  }

  void _triggerSos() {
    CampusSosDialog.show(
      context: context,
      onConfirmed: () {
        _showToast(
          'Campus SOS Triggered',
          'DIU Security informed of your live Ashulia coordinates.',
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final departingRidesAsync = ref.watch(departingSoonRidesStreamProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          ref.invalidate(departingSoonRidesStreamProvider);
          ref.invalidate(departingSoonRidesProvider);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Campus Security & Location Strip
              CampusSecurityStrip(
                onTapLocation: () {
                  _showToast('Location refreshed', 'Coordinates updated to DIU Smart City');
                },
              ),

              // 2. Uber-Style "Where to?" Search Container (Prominent Primary Action)
              DestinationSearchCard(
                onTapSearch: () {
                  ref.read(rideSearchFilterProvider.notifier).setAllRidesMode(true);
                  widget.onNavigateTab(1);
                },
                onSelectDestination: (destination) {
                  ref.read(rideSearchFilterProvider.notifier).setAllRidesMode(false);
                  widget.onSearchQuery(destination);
                  widget.onNavigateTab(1);
                },
              ),

              // 3. Campus Ride Categories (UberX Carpool, Moto, Shuttle, Female-Only)
              CampusCategoryGrid(
                selectedType: _selectedCategory,
                femaleOnlySelected: _femaleOnlyCategory,
                onSelectCategory: _onCategorySelected,
              ),

              // 4. Interactive Live Map Preview
              InteractiveMapPreview(
                onSelectPin: _handlePinTap,
                onRecenter: () {
                  _showToast('Map Recentered', 'Target locked to DSC Academic Circle');
                },
              ),

              // 5. Live Departing Soon Nearby Rides Carousel (Realtime Multi-App Synced)
              departingRidesAsync.when(
                data: (rides) => DepartingRidesCarousel(
                  rides: rides,
                  onRequestSeat: _handleRequestSeat,
                  onSeeAll: () {
                    ref.read(rideSearchFilterProvider.notifier).setAllRidesMode(true);
                    ref.read(rideSearchFilterProvider.notifier).clearFilters();
                    widget.onNavigateTab(1);
                  },
                ),
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                ),
                error: (err, _) => Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('Failed to load rides: $err', style: AppTypography.bodyMd),
                ),
              ),

              // 6. Community Trust & Campus SOS Card
              CommunityTrustSosCard(
                onTriggerSos: _triggerSos,
                onCallControl: () {
                  _showToast('Calling Control Desk', 'DIU DSC Security: Ext. 4410');
                },
              ),

              // 7. Campus Web Portals (In-App WebView & Firebase Domain)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.outlineVariant.withOpacity(0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.language, size: 18, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Campus Web & Online Portals',
                            style: AppTypography.titleSm.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const CampusWebViewScreen(
                                      title: 'DIU Student Portal',
                                      initialUrl: 'https://studentportal.diu.edu.bd',
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.school, size: 16),
                              label: const Text('DIU Portal', style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const CampusWebViewScreen(
                                      title: 'DIU Ride Web (Firebase)',
                                      initialUrl: 'https://diu-ride.web.app',
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.public, size: 16),
                              label: const Text('DIU Ride Web', style: TextStyle(fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
