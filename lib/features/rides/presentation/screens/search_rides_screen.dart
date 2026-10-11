import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/features/booking/presentation/widgets/booking_confirmation_sheet.dart';
import 'package:diu_ride/features/tracking/presentation/screens/ride_details_tracking_screen.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';
import 'package:diu_ride/features/rides/presentation/widgets/ride_result_card.dart';
import 'package:diu_ride/features/rides/presentation/widgets/search_filter_chips.dart';
import 'package:diu_ride/features/rides/presentation/widgets/search_route_card.dart';

class SearchRidesScreen extends ConsumerStatefulWidget {
  const SearchRidesScreen({super.key});

  @override
  ConsumerState<SearchRidesScreen> createState() => _SearchRidesScreenState();
}

class _SearchRidesScreenState extends ConsumerState<SearchRidesScreen> {
  final _searchController = TextEditingController();
  String _selectedQuickTag = 'All';

  final List<String> _quickTags = [
    'All',
    'Uttara',
    'Mirpur',
    'Dhanmondi',
    'Gate 1',
    'Birulia',
    'Ashulia',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showBookingSheet(ride) {
    BookingConfirmationSheet.show(
      context: context,
      ride: ride,
      onBookingSuccess: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            content: Text(
              'Seat Reserved! Driver ${ride.driverName} notified.',
              style: AppTypography.bodyMdMedium.copyWith(color: Colors.white),
            ),
          ),
        );
      },
    );
  }

  void _onQuickTagSelected(String tag) {
    setState(() => _selectedQuickTag = tag);
    final notifier = ref.read(rideSearchFilterProvider.notifier);
    if (tag == 'All') {
      _searchController.clear();
      notifier.setGeneralSearch('');
    } else {
      _searchController.text = tag;
      notifier.setGeneralSearch(tag);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filterState = ref.watch(rideSearchFilterProvider);
    final filterNotifier = ref.read(rideSearchFilterProvider.notifier);
    final resultsAsync = ref.watch(searchRidesResultsProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top Mode Switcher (All Rides vs Route Planner)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          if (!filterState.isAllRidesMode) {
                            filterNotifier.setAllRidesMode(true);
                          }
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: filterState.isAllRidesMode ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: filterState.isAllRidesMode
                                ? [const BoxShadow(color: AppColors.cardShadow, blurRadius: 4, offset: Offset(0, 1))]
                                : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.two_wheeler,
                                size: 16,
                                color: filterState.isAllRidesMode ? AppColors.primary : AppColors.outline,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'All Moto Rides',
                                style: AppTypography.labelMd.copyWith(
                                  fontWeight: filterState.isAllRidesMode ? FontWeight.bold : FontWeight.w500,
                                  color: filterState.isAllRidesMode ? AppColors.primary : AppColors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          if (filterState.isAllRidesMode) {
                            filterNotifier.setAllRidesMode(false);
                            if (filterState.pickupQuery.isEmpty) {
                              filterNotifier.setPickup('DIU Smart City, Ashulia');
                              filterNotifier.setDropoff('Uttara Sector 11');
                            }
                          }
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: !filterState.isAllRidesMode ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: !filterState.isAllRidesMode
                                ? [const BoxShadow(color: AppColors.cardShadow, blurRadius: 4, offset: Offset(0, 1))]
                                : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.route,
                                size: 16,
                                color: !filterState.isAllRidesMode ? AppColors.primary : AppColors.outline,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Bike Route',
                                style: AppTypography.labelMd.copyWith(
                                  fontWeight: !filterState.isAllRidesMode ? FontWeight.bold : FontWeight.w500,
                                  color: !filterState.isAllRidesMode ? AppColors.primary : AppColors.onSurfaceVariant,
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
            ),

            // Mode 1: All Rides - Live Search Input
            if (filterState.isAllRidesMode) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.outlineVariant.withOpacity(0.6)),
                    boxShadow: const [
                      BoxShadow(color: AppColors.cardShadow, blurRadius: 6, offset: Offset(0, 2)),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) {
                      filterNotifier.setGeneralSearch(val);
                      if (val.isEmpty) setState(() => _selectedQuickTag = 'All');
                    },
                    decoration: InputDecoration(
                      hintText: 'Search destination, pickup, driver, vehicle...',
                      hintStyle: AppTypography.bodyMd.copyWith(color: AppColors.outline),
                      prefixIcon: const Icon(Icons.search, color: AppColors.primary),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                filterNotifier.setGeneralSearch('');
                                setState(() => _selectedQuickTag = 'All');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
              ),

              // Quick Location Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: _quickTags.map((tag) {
                    final isSel = _selectedQuickTag == tag;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(tag),
                        selected: isSel,
                        onSelected: (_) => _onQuickTagSelected(tag),
                        selectedColor: AppColors.primaryContainer,
                        checkmarkColor: AppColors.primary,
                        labelStyle: TextStyle(
                          fontSize: 12,
                          color: isSel ? AppColors.primary : AppColors.onSurfaceVariant,
                          fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                        ),
                        backgroundColor: AppColors.surfaceContainerLow,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: isSel ? AppColors.primary : Colors.transparent,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ] else ...[
              // Mode 2: Route Planner (Pickup & Dropoff Cards)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: SearchRouteCard(
                  pickup: filterState.pickupQuery,
                  dropoff: filterState.dropoffQuery,
                  seats: filterState.seatsNeeded,
                  departureTime: filterState.departureTime,
                  onPickupChanged: filterNotifier.setPickup,
                  onDropoffChanged: filterNotifier.setDropoff,
                  onSwap: filterNotifier.swapLocations,
                  onGpsTap: () {
                    filterNotifier.setPickup('DIU Smart City, Ashulia');
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Pickup set to current campus location.')),
                    );
                  },
                  onSeatsChanged: filterNotifier.setSeatsNeeded,
                  onSelectTime: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Departure scheduled for today.')),
                    );
                  },
                ),
              ),
            ],

            // Horizontal Filter Chips (Vehicles, Female only, Lowest price)
            SearchFilterChips(
              filterState: filterState,
              notifier: filterNotifier,
            ),
            const SizedBox(height: 4),

            // Results count status bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
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
                      resultsAsync.when(
                        data: (rides) => Text(
                          '${rides.length} Rides Available',
                          style: AppTypography.labelLg.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.onSurface,
                          ),
                        ),
                        loading: () => Text(
                          'Searching rides...',
                          style: AppTypography.labelLg,
                        ),
                        error: (_, __) => Text(
                          '0 Rides Available',
                          style: AppTypography.labelLg,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '• Ashulia Corridor',
                        style: AppTypography.labelSm.copyWith(color: AppColors.outline),
                      ),
                    ],
                  ),
                  if (filterState.generalSearchQuery.isNotEmpty || filterState.vehicleType != null || filterState.femaleOnly)
                    InkWell(
                      onTap: () {
                        _searchController.clear();
                        filterNotifier.clearFilters();
                        setState(() => _selectedQuickTag = 'All');
                      },
                      child: Text(
                        'Clear Filters',
                        style: AppTypography.labelSm.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Results feed
            Expanded(
              child: resultsAsync.when(
                data: (rides) {
                  if (rides.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.commute, size: 52, color: AppColors.outlineVariant),
                            const SizedBox(height: 12),
                            Text(
                              'No matching rides found',
                              style: AppTypography.headlineSm.copyWith(color: AppColors.onSurface),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Try searching a different location or reset filters to see all available rides.',
                              style: AppTypography.bodyMd.copyWith(color: AppColors.outline),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () {
                                _searchController.clear();
                                filterNotifier.clearFilters();
                                setState(() => _selectedQuickTag = 'All');
                              },
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('View All Campus Rides'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: () async {
                      ref.invalidate(searchRidesResultsProvider);
                      ref.invalidate(departingSoonRidesProvider);
                      ref.invalidate(allAvailableRidesProvider);
                    },
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                      itemCount: rides.length,
                      itemBuilder: (context, index) {
                        final ride = rides[index];
                        return RideResultCard(
                          ride: ride,
                          onBook: () => _showBookingSheet(ride),
                          onTapDetails: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => RideDetailsTrackingScreen(
                                  rideId: ride.id,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
                error: (err, _) => Center(
                  child: Text('Error loading rides: $err'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
