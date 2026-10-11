import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/core/utils/date_time_utils.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/booking/presentation/widgets/booking_confirmation_sheet.dart';
import 'package:diu_ride/features/chat/presentation/screens/chat_screen.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';
import 'package:diu_ride/features/rides/data/models/vehicle_model.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';
import 'package:diu_ride/features/rides/presentation/widgets/post_ride_request_sheet.dart';
import 'package:diu_ride/features/tracking/presentation/screens/ride_details_tracking_screen.dart';

class AllSharedRidesScreen extends ConsumerStatefulWidget {
  const AllSharedRidesScreen({super.key});

  @override
  ConsumerState<AllSharedRidesScreen> createState() => _AllSharedRidesScreenState();
}

class _AllSharedRidesScreenState extends ConsumerState<AllSharedRidesScreen> {
  int _selectedMode = 0; // 0 = Available Bikes, 1 = Student Requests
  String _selectedLocation = 'All';
  bool _sortByLowestPrice = false;
  bool _femaleOnly = false;
  final TextEditingController _searchController = TextEditingController();

  final List<String> _locationFilters = [
    'All',
    'Uttara',
    'Mirpur',
    'Dhanmondi',
    'Ashulia',
    'Birulia',
    'Savar',
    'Mohakhali',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _handleBooking(RideModel ride) {
    BookingConfirmationSheet.show(
      context: context,
      ride: ride,
      onBookingSuccess: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1C1C1E),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            content: Row(
              children: [
                const Icon(Icons.two_wheeler, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Moto Seat Requested from ${ride.driverName}! ৳${ride.farePerSeat.toInt()}',
                    style: AppTypography.labelMd.copyWith(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final allRidesAsync = ref.watch(allAvailableRidesProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Column(
          children: [
            // 1. Top Apple-style Search & Location Filter Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'All Shared Moto Rides',
                            style: AppTypography.headlineSm.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF1C1C1E),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Verified peer bikes commuting across Dhaka',
                            style: AppTypography.labelSm.copyWith(
                              color: const Color(0xFF8E8E93),
                            ),
                          ),
                        ],
                      ),
                      // Bikes Only Pill
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.two_wheeler, size: 14, color: Color(0xFF2E7D32)),
                            SizedBox(width: 4),
                            Text(
                              'Bikes Only',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF2E7D32),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Sub-tab switcher: Available Bikes vs Student Requests
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E5EA),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _selectedMode = 0),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: _selectedMode == 0 ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(11),
                                boxShadow: _selectedMode == 0
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
                                    size: 16,
                                    color: _selectedMode == 0
                                        ? const Color(0xFFE65100)
                                        : const Color(0xFF8E8E93),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Available Bikes',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: _selectedMode == 0 ? FontWeight.bold : FontWeight.w600,
                                      color: _selectedMode == 0
                                          ? const Color(0xFF141416)
                                          : const Color(0xFF8E8E93),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _selectedMode = 1),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: _selectedMode == 1 ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(11),
                                boxShadow: _selectedMode == 1
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
                                    Icons.hail,
                                    size: 16,
                                    color: _selectedMode == 1
                                        ? const Color(0xFFE65100)
                                        : const Color(0xFF8E8E93),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Student Requests',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: _selectedMode == 1 ? FontWeight.bold : FontWeight.w600,
                                      color: _selectedMode == 1
                                          ? const Color(0xFF141416)
                                          : const Color(0xFF8E8E93),
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

                  // Search input
                  Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F2F7),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Filter by route, destination or driver...',
                        hintStyle: AppTypography.bodyMd.copyWith(color: const Color(0xFF8E8E93)),
                        prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF8E8E93)),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Location Filter Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        ..._locationFilters.map((loc) {
                          final isSelected = _selectedLocation == loc;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedLocation = loc;
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                decoration: BoxDecoration(
                                  color: isSelected ? const Color(0xFFE65100) : Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isSelected
                                        ? const Color(0xFFE65100)
                                        : Colors.black.withOpacity(0.08),
                                  ),
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                            color: const Color(0xFFE65100).withOpacity(0.25),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Text(
                                  loc,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                    color: isSelected ? Colors.white : const Color(0xFF3A3A3C),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),

                        // Price Sort Toggle Pill
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _sortByLowestPrice = !_sortByLowestPrice;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: _sortByLowestPrice
                                  ? const Color(0xFF34C759)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _sortByLowestPrice
                                    ? const Color(0xFF34C759)
                                    : Colors.black.withOpacity(0.08),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.swap_vert,
                                  size: 14,
                                  color: _sortByLowestPrice ? Colors.white : const Color(0xFF3A3A3C),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Price: Lowest',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: _sortByLowestPrice ? FontWeight.w700 : FontWeight.w600,
                                    color: _sortByLowestPrice ? Colors.white : const Color(0xFF3A3A3C),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Female Only Toggle
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _femaleOnly = !_femaleOnly;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: _femaleOnly ? const Color(0xFFE91E63) : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _femaleOnly
                                    ? const Color(0xFFE91E63)
                                    : Colors.black.withOpacity(0.08),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.female,
                                  size: 14,
                                  color: _femaleOnly ? Colors.white : const Color(0xFFE91E63),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Women Safe',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: _femaleOnly ? FontWeight.w700 : FontWeight.w600,
                                    color: _femaleOnly ? Colors.white : const Color(0xFF3A3A3C),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 2. Rides List or Student Requests
            Expanded(
              child: _selectedMode == 1
                  ? _buildStudentRequestsView()
                  : allRidesAsync.when(
                      data: (rides) {
                        // Filter strictly to bikes
                        var filtered = rides.where((r) => r.vehicle.type == VehicleType.bike).toList();

                        // Filter by location
                        if (_selectedLocation != 'All') {
                          final query = _selectedLocation.toLowerCase();
                          filtered = filtered.where((r) {
                            return r.destinationName.toLowerCase().contains(query) ||
                                (r.destinationSubtitle?.toLowerCase().contains(query) ?? false) ||
                                r.originName.toLowerCase().contains(query) ||
                                r.routeCorridor.toLowerCase().contains(query);
                          }).toList();
                        }

                        // Filter by search text
                        final search = _searchController.text.trim().toLowerCase();
                        if (search.isNotEmpty) {
                          filtered = filtered.where((r) {
                            return r.destinationName.toLowerCase().contains(search) ||
                                r.originName.toLowerCase().contains(search) ||
                                r.driverName.toLowerCase().contains(search) ||
                                r.vehicle.modelName.toLowerCase().contains(search);
                          }).toList();
                        }

                        // Female Only
                        if (_femaleOnly) {
                          filtered = filtered.where((r) => r.isFemaleOnly).toList();
                        }

                        // Sort by price
                        if (_sortByLowestPrice) {
                          filtered.sort((a, b) => a.farePerSeat.compareTo(b.farePerSeat));
                        }

                        if (filtered.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF3E0),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Icon(Icons.two_wheeler, size: 32, color: Color(0xFFE65100)),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  'No Moto Rides Found',
                                  style: AppTypography.headlineSm.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'No peer rides matching "$_selectedLocation". Try clearing filters.',
                                  style: AppTypography.labelSm.copyWith(color: const Color(0xFF8E8E93)),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _selectedLocation = 'All';
                                      _searchController.clear();
                                      _femaleOnly = false;
                                      _sortByLowestPrice = false;
                                    });
                                  },
                                  icon: const Icon(Icons.refresh, size: 16),
                                  label: const Text('Reset All Filters'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF141416),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        return RefreshIndicator(
                          color: const Color(0xFFE65100),
                          onRefresh: () async {
                            ref.invalidate(allAvailableRidesProvider);
                          },
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final ride = filtered[index];
                              return _buildCleanMotoRideCard(ride);
                            },
                          ),
                        );
                      },
                      loading: () => const Center(
                        child: CircularProgressIndicator(color: Color(0xFFE65100)),
                      ),
                      error: (err, _) => Center(
                        child: Text('Error: $err', style: AppTypography.bodyMd),
                      ),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          PostRideRequestSheet.show(context);
        },
        backgroundColor: const Color(0xFF141416),
        icon: const Icon(Icons.hail, color: Color(0xFFFFA000), size: 20),
        label: const Text(
          'Request a Ride',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildCleanMotoRideCard(RideModel ride) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () {
            // Open full ride details modal/screen
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => RideDetailsTrackingScreen(rideId: ride.id),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top: Driver Header & Tags
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: const Color(0xFFFFF3E0),
                          child: Text(
                            ride.driverName.isNotEmpty ? ride.driverName[0].toUpperCase() : 'D',
                            style: const TextStyle(
                              color: Color(0xFFE65100),
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ride.driverName,
                              style: AppTypography.labelMd.copyWith(
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF141416),
                              ),
                            ),
                            Row(
                              children: [
                                const Icon(Icons.star, size: 12, color: Color(0xFFFFA000)),
                                const SizedBox(width: 3),
                                Text(
                                  '${ride.driverRating.toStringAsFixed(1)} • ${ride.driverDept}',
                                  style: AppTypography.labelSm.copyWith(
                                    color: const Color(0xFF8E8E93),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),

                    // Price & 1 Seat Badge
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '৳${ride.farePerSeat.toInt()}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFE65100),
                            letterSpacing: -0.5,
                          ),
                        ),
                        const Text(
                          '1 Moto Seat',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF34C759),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                const Divider(height: 1, color: Color(0xFFF2F2F7)),
                const SizedBox(height: 12),

                // Middle: Route (From -> To)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Color(0xFF2E7D32),
                            shape: BoxShape.circle,
                          ),
                        ),
                        Container(
                          width: 2,
                          height: 24,
                          color: const Color(0xFFE5E5EA),
                        ),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFF3B30),
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
                              Expanded(
                                child: Text(
                                  ride.originName,
                                  style: AppTypography.labelMd.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF1C1C1E),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                DateTimeUtils.formatTime(ride.departureTime),
                                style: AppTypography.labelSm.copyWith(
                                  color: const Color(0xFF8E8E93),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            ride.destinationName,
                            style: AppTypography.labelMd.copyWith(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF141416),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Bottom: Motorcycle Model & Action Buttons
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2F2F7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.two_wheeler, size: 13, color: Color(0xFF3A3A3C)),
                          const SizedBox(width: 5),
                          Text(
                            ride.vehicle.modelName,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF3A3A3C),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.shield, size: 12, color: Color(0xFF2E7D32)),
                          SizedBox(width: 4),
                          Text(
                            'Helmet Ready',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF2E7D32),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),

                    // Direct SMS button
                    OutlinedButton.icon(
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
                      icon: const Icon(Icons.chat_bubble_outline, size: 13),
                      label: const Text('SMS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF141416),
                        side: BorderSide(color: const Color(0xFF141416).withOpacity(0.2)),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        minimumSize: Size.zero,
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Book / Details Button
                    ElevatedButton(
                      onPressed: () => _handleBooking(ride),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF141416),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        minimumSize: Size.zero,
                      ),
                      child: const Text(
                        'Request Seat',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStudentRequestsView() {
    final ridesRepo = ref.watch(ridesRepositoryProvider);
    final user = ref.watch(authNotifierProvider).user;

    return FutureBuilder<List<dynamic>>(
      future: ridesRepo.getPassengerRequests(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFFE65100)));
        }

        final requests = snapshot.data ?? [];
        if (requests.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.hail, size: 32, color: Color(0xFFE65100)),
                ),
                const SizedBox(height: 14),
                Text(
                  'No Student Requests Yet',
                  style: AppTypography.headlineSm.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  'Students who request a ride will appear here.\nAny biker can accept their request to ride together.',
                  textAlign: TextAlign.center,
                  style: AppTypography.labelSm.copyWith(color: const Color(0xFF8E8E93)),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => PostRideRequestSheet.show(context),
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: const Text('Post a Ride Request Now'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF141416),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          color: const Color(0xFFE65100),
          onRefresh: () async {
            setState(() {});
          },
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final req = requests[index];
              final isMap = req is Map<String, dynamic>;
              final id = isMap ? (req['id'] ?? '') : (req.id ?? '');
              final pName = isMap ? (req['passengerName'] ?? 'Student') : (req.passengerName ?? 'Student');
              final pDept = isMap ? (req['passengerDept'] ?? 'CSE') : (req.passengerDept ?? 'CSE');
              final pPhone = isMap ? (req['passengerPhone'] ?? '') : (req.passengerPhone ?? '');
              final pickup = isMap ? (req['pickup'] ?? '') : (req.pickup ?? '');
              final dropoff = isMap ? (req['dropoff'] ?? '') : (req.dropoff ?? '');
              final time = isMap ? (req['requestedTime'] ?? '') : (req.requestedTime ?? '');
              final fare = isMap ? (req['proposedFare'] ?? 50.0) : (req.proposedFare ?? 50.0);
              final status = isMap ? (req['status'] ?? 'open') : (req.status ?? 'open');
              final isAccepted = status == 'accepted';

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isAccepted ? const Color(0xFF34C759).withOpacity(0.4) : Colors.black.withOpacity(0.06),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: const Color(0xFFFFF3E0),
                          child: Text(
                            pName.isNotEmpty ? pName[0].toUpperCase() : 'S',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFE65100)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(pName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              Text('$pDept • Requested: $time', style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isAccepted ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '৳${fare is num ? fare.toInt() : fare}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: isAccepted ? const Color(0xFF2E7D32) : const Color(0xFFE65100),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F9FA),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.trip_origin, size: 14, color: Color(0xFF2E7D32)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(pickup, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                          const Icon(Icons.arrow_forward, size: 12, color: Colors.grey),
                          const SizedBox(width: 6),
                          const Icon(Icons.location_on, size: 14, color: Color(0xFFFF3B30)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(dropoff, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (isAccepted)
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ChatScreen(
                                      rideId: id,
                                      peerName: pName,
                                      vehicleModel: 'Student Ride Request',
                                      peerPhone: pPhone,
                                      peerRole: 'Passenger',
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.chat, size: 15),
                              label: const Text('Chat with Passenger'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF34C759),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                                  requestId: id,
                                  driverId: currentUserId,
                                  driverName: currentUserName,
                                  driverPhone: currentUserPhone,
                                  driverBike: 'Campus Motorcycle',
                                );

                                if (ok && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      backgroundColor: const Color(0xFF1C1C1E),
                                      content: Text('Ride Request Accepted! You will commute with $pName.'),
                                    ),
                                  );
                                  setState(() {});
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ChatScreen(
                                        rideId: id,
                                        peerName: pName,
                                        vehicleModel: 'Accepted Commute',
                                        peerPhone: pPhone,
                                        peerRole: 'Passenger',
                                      ),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.check_circle_outline, size: 16),
                              label: const Text('Accept Request (রাইড গ্রহণ করুন)'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF141416),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
    );
  }
}
