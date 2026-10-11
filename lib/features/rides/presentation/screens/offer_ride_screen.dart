import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/constants/campus_locations.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/rides/data/models/vehicle_model.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';

class OfferRideScreen extends ConsumerStatefulWidget {
  final VoidCallback onRidePublished;

  const OfferRideScreen({
    super.key,
    required this.onRidePublished,
  });

  @override
  ConsumerState<OfferRideScreen> createState() => _OfferRideScreenState();
}

class _OfferRideScreenState extends ConsumerState<OfferRideScreen> {
  final _originController = TextEditingController(text: 'DIU Smart City, Ashulia');
  final _destinationController = TextEditingController(text: 'Uttara Sector 10');
  final _waypointController = TextEditingController();
  final _fareController = TextEditingController(text: '50');

  bool _isWaypointOpen = false;
  int _selectedDateIndex = 0; // 0: Today, 1: Tomorrow, 2: Custom
  TimeOfDay _departureTime = const TimeOfDay(hour: 16, minute: 30);
  final VehicleType _vehicleType = VehicleType.bike; // Strictly motorbikes only
  final int _seats = 1; // 1 passenger seat for bikes
  String _bikeModel = 'Yamaha FZ-X';
  bool _hasPassengerHelmet = true;
  bool _isFemaleOnly = false;
  bool _isPublishing = false;

  final List<String> _availableBikes = [
    'Yamaha FZ-X',
    'Yamaha FZ-S V3',
    'Honda CB Shine',
    'Honda X-Blade',
    'Suzuki Gixxer SF',
    'Bajaj Pulsar NS160',
    'TVS Apache RTR 4V',
  ];

  @override
  void dispose() {
    _originController.dispose();
    _destinationController.dispose();
    _waypointController.dispose();
    _fareController.dispose();
    super.dispose();
  }

  void _adjustTime(int deltaMinutes) {
    int totalMinutes = _departureTime.hour * 60 + _departureTime.minute + deltaMinutes;
    if (totalMinutes < 0) totalMinutes += 1440;
    if (totalMinutes >= 1440) totalMinutes -= 1440;
    setState(() {
      _departureTime = TimeOfDay(hour: totalMinutes ~/ 60, minute: totalMinutes % 60);
    });
  }

  void _publishRide() async {
    final origin = _originController.text.trim();
    final dest = _destinationController.text.trim();
    final fare = double.tryParse(_fareController.text.trim()) ?? 50.0;

    if (origin.isEmpty || dest.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please specify origin and destination.')),
      );
      return;
    }

    setState(() => _isPublishing = true);

    final vehicle = VehicleModel(
      id: 'v_user_offered',
      type: _vehicleType,
      modelName: _bikeModel,
      color: 'Matte Blue Metallic',
      licensePlate: 'Dhaka Metro-HA 24-8891',
      hasAc: false,
      hasPassengerHelmet: _hasPassengerHelmet,
      isSmokeFree: true,
      hasPhoneCharger: true,
      hasLuggageSpace: false,
    );

    final now = DateTime.now();
    final departureDateTime = DateTime(
      now.year,
      now.month,
      now.day + _selectedDateIndex,
      _departureTime.hour,
      _departureTime.minute,
    );

    final currentUser = ref.read(authNotifierProvider).user;

    await ref.read(ridesRepositoryProvider).createRide(
          driverId: currentUser?.id,
          driverName: currentUser?.name ?? 'DIU Student Driver',
          driverPhone: currentUser?.phone,
          driverDepartment: currentUser?.department ?? 'CSE',
          originName: origin,
          originLat: CampusLocations.diuCenterLat,
          originLng: CampusLocations.diuCenterLng,
          destinationName: dest,
          destinationLat: CampusLocations.uttaraHouseBuilding.latitude,
          destinationLng: CampusLocations.uttaraHouseBuilding.longitude,
          waypointName: _isWaypointOpen ? _waypointController.text.trim() : null,
          departureTime: departureDateTime,
          vehicle: vehicle,
          availableSeats: _seats,
          farePerSeat: fare,
          isFemaleOnly: _isFemaleOnly,
        );

    if (currentUser != null) {
      final updated = currentUser.copyWith(
        totalRidesAsDriver: currentUser.totalRidesAsDriver + 1,
        isDriverRegistered: true,
        vehicleInfo: '${vehicle.modelName} (${vehicle.licensePlate})',
      );
      await ref.read(authRepositoryProvider).updateProfile(updated);
    }

    setState(() => _isPublishing = false);

    if (mounted) {
      ref.invalidate(departingSoonRidesProvider);
      ref.invalidate(searchRidesResultsProvider);
      ref.invalidate(allAvailableRidesProvider);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Text(
            'Ride Published! Status: PUBLISHED • Visible to DIU Students',
            style: AppTypography.bodyMdMedium.copyWith(color: Colors.white),
          ),
        ),
      );
      widget.onRidePublished();
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatTime =
        '${_departureTime.hourOfPeriod.toString().padLeft(2, '0')}:${_departureTime.minute.toString().padLeft(2, '0')}';
    final period = _departureTime.period == DayPeriod.am ? 'AM' : 'PM';

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Status & Driver Context Pill
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.primaryFixed.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.verified_user, color: AppColors.primary, size: 15),
                        const SizedBox(width: 4),
                        Text(
                          'Verified Driver (DIU CSE 2021)',
                          style: AppTypography.labelSm.copyWith(
                            color: AppColors.onPrimaryFixed,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.eco, color: AppColors.primary, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        'Eco Commute #42',
                        style: AppTypography.labelSm.copyWith(color: AppColors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Text('Offer a Campus Ride', style: AppTypography.headlineLg),
              const SizedBox(height: 4),
              Text(
                'Share empty seats, offset fuel costs, and support your DIU peers traveling safely between campus and Dhaka.',
                style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 12),

              // STEP 1: ROUTE SETUP CARD
              _buildSectionCard(
                stepNum: '1',
                title: 'Campus Route',
                extraAction: TextButton.icon(
                  onPressed: () {
                    final oldOrigin = _originController.text;
                    _originController.text = _destinationController.text;
                    _destinationController.text = oldOrigin;
                    setState(() {});
                  },
                  icon: const Icon(Icons.swap_vert, size: 16, color: AppColors.secondary),
                  label: Text('Reverse', style: AppTypography.labelSm.copyWith(color: AppColors.secondary)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Origin
                    Text('Origin / DIU Spot', style: AppTypography.labelSm),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _originController,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.trip_origin, color: AppColors.primary),
                        hintText: 'Choose campus pickup point',
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Origin Presets
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildPresetChip('Main Gate', 'Main Gate - Daffodil Smart City', _originController),
                          _buildPresetChip('Transport Terminal', 'Transport Terminal (Bus Bay)', _originController),
                          _buildPresetChip('Daffodil Tower', 'Daffodil Tower / AB-4', _originController),
                          _buildPresetChip('Lake Bridge', 'Campus Lake Bridge', _originController),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Waypoint trigger
                    InkWell(
                      onTap: () => setState(() => _isWaypointOpen = !_isWaypointOpen),
                      child: Row(
                        children: [
                          Icon(
                            _isWaypointOpen ? Icons.remove_circle : Icons.add_circle,
                            size: 18,
                            color: AppColors.secondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _isWaypointOpen ? 'Remove Campus Pickup Stop' : 'Add Campus Pickup Stop',
                            style: AppTypography.labelSm.copyWith(
                              color: AppColors.secondary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (_isWaypointOpen) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _waypointController,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.add_location, color: AppColors.secondary),
                          hintText: 'e.g. Birulia Bridge / Khagan Bazar',
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),

                    // Destination
                    Text('Destination in Dhaka', style: AppTypography.labelSm),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _destinationController,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.location_on, color: AppColors.secondary),
                        hintText: 'Search Dhaka drop-off...',
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Destination Presets
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildPresetChip('Uttara', 'Uttara Sector 10/House Building', _destinationController),
                          _buildPresetChip('Mirpur 1', 'Mirpur 1 / Sony Square', _destinationController),
                          _buildPresetChip('Dhanmondi 27', 'Dhanmondi 27 / Sobhanbag', _destinationController),
                          _buildPresetChip('Mohakhali', 'Mohakhali Flyover', _destinationController),
                          _buildPresetChip('ECB', 'ECB Chattar', _destinationController),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // STEP 2: SCHEDULE & TIME CARD
              _buildSectionCard(
                stepNum: '2',
                title: 'Departure Schedule',
                extraTag: 'Post-Class Rush Hour',
                child: Column(
                  children: [
                    // Date selector chips
                    Row(
                      children: [
                        _buildDateChip(0, 'Today', 'Mon, 28 Apr'),
                        const SizedBox(width: 8),
                        _buildDateChip(1, 'Tomorrow', 'Tue, 29 Apr'),
                        const SizedBox(width: 8),
                        _buildDateChip(2, 'Custom', 'Pick Date'),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Time Stepper
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Estimated Roll-out', style: AppTypography.labelSm),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    formatTime,
                                    style: AppTypography.headlineMd.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    period,
                                    style: AppTypography.labelLg.copyWith(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text('(Shift Ends)', style: AppTypography.labelSm),
                                ],
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              _buildStepBtn(Icons.remove, () => _adjustTime(-15)),
                              const SizedBox(width: 8),
                              Text('15m', style: AppTypography.labelSm.copyWith(fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                              _buildStepBtn(Icons.add, () => _adjustTime(15)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // STEP 3: MOTORBIKE & HELMET CARD
              _buildSectionCard(
                stepNum: '3',
                title: 'Motorbike & Helmet',
                extraTag: '1 Passenger Seat',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Motorbike Model Chips
                    Text('Your Motorcycle Model', style: AppTypography.labelSm),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: _availableBikes.map((bike) {
                          final isSelected = _bikeModel == bike;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: InkWell(
                              onTap: () => setState(() => _bikeModel = bike),
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isSelected ? const Color(0xFFE65100) : Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isSelected ? const Color(0xFFE65100) : const Color(0xFFE5E5EA),
                                    width: isSelected ? 1.5 : 1.0,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: isSelected
                                          ? const Color(0xFFE65100).withOpacity(0.2)
                                          : Colors.black.withOpacity(0.03),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.two_wheeler,
                                      size: 16,
                                      color: isSelected ? Colors.white : const Color(0xFF1C1C1E),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      bike,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: isSelected ? Colors.white : const Color(0xFF1C1C1E),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Fixed Seat Capacity (1 Passenger Seat)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2F2F7),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.person, size: 18, color: Color(0xFFE65100)),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '1 Passenger Seat Available',
                                    style: AppTypography.bodyMdMedium.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  Text(
                                    'Fixed standard motorcycle capacity',
                                    style: AppTypography.labelSm.copyWith(color: const Color(0xFF8E8E93)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF3E0),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              '1 Seat',
                              style: TextStyle(
                                color: Color(0xFFE65100),
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Helmet Checkbox
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE5E5EA)),
                      ),
                      child: Row(
                        children: [
                          Checkbox(
                            value: _hasPassengerHelmet,
                            activeColor: const Color(0xFFE65100),
                            onChanged: (val) => setState(() => _hasPassengerHelmet = val ?? true),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.sports_motorsports, size: 16, color: Color(0xFFE65100)),
                                    const SizedBox(width: 5),
                                    Text(
                                      'Clean Passenger Helmet Provided',
                                      style: AppTypography.bodyMdMedium.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                                Text(
                                  'DOT / BSTI certified helmet for your passenger',
                                  style: AppTypography.labelSm.copyWith(fontSize: 10.5, color: const Color(0xFF8E8E93)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Female-Only Toggle
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Checkbox(
                            value: _isFemaleOnly,
                            activeColor: AppColors.primary,
                            onChanged: (val) => setState(() => _isFemaleOnly = val ?? false),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.female, size: 16, color: AppColors.primary),
                                    const SizedBox(width: 4),
                                    Text('Female Students Only', style: AppTypography.bodyMdMedium),
                                  ],
                                ),
                                Text(
                                  'Restricted to verified female DIU ID cardholders',
                                  style: AppTypography.labelSm.copyWith(fontSize: 10.5),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // STEP 4: FAIR STUDENT FARE (FUEL SHARING)
              _buildSectionCard(
                stepNum: '4',
                title: 'Fair Student Fare',
                extraTag: 'DIU AI Calc',
                child: Column(
                  children: [
                    // Recommended corridor range banner
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
                              const Icon(Icons.local_gas_station, color: AppColors.secondary, size: 22),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Recommended Corridor Range', style: AppTypography.labelSm),
                                  Text(
                                    '৳40 – ৳55 / passenger',
                                    style: AppTypography.bodyMdMedium.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.secondaryFixed.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Cost Split',
                              style: AppTypography.labelSm.copyWith(
                                color: AppColors.secondary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Fare input and quick presets
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _fareController,
                            keyboardType: TextInputType.number,
                            style: AppTypography.headlineSm.copyWith(fontWeight: FontWeight.bold),
                            decoration: const InputDecoration(
                              prefixText: '৳ ',
                              suffixText: '/ seat',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _buildQuickFare('৳40', '40'),
                        const SizedBox(width: 6),
                        _buildQuickFare('৳50', '50'),
                        const SizedBox(width: 6),
                        _buildQuickFare('৳60', '60'),
                      ],
                    ),
                    const SizedBox(height: 10),

                    Row(
                      children: [
                        const Icon(Icons.info_outline, size: 14, color: AppColors.outline),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'DIU Carpool policy forbids commercial profit. Set fair fuel contribution only.',
                            style: AppTypography.labelSm.copyWith(color: AppColors.outline, fontSize: 10.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // SUBMIT BUTTON
              ElevatedButton(
                onPressed: _isPublishing ? null : _publishRide,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryContainer,
                  foregroundColor: AppColors.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                child: _isPublishing
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle_outline, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Publish Campus Ride (৳${_fareController.text}/seat)',
                            style: AppTypography.labelLg.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String stepNum,
    required String title,
    String? extraTag,
    Widget? extraAction,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: AppColors.primaryFixed,
                    child: Text(
                      stepNum,
                      style: AppTypography.labelSm.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(title, style: AppTypography.bodyLgMedium.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
              if (extraTag != null)
                Text(
                  extraTag,
                  style: AppTypography.labelSm.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                )
              else if (extraAction != null)
                extraAction,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildPresetChip(String label, String value, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        label: Text(label),
        labelStyle: AppTypography.labelSm.copyWith(fontSize: 11),
        backgroundColor: AppColors.surfaceContainer,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onPressed: () => setState(() => controller.text = value),
      ),
    );
  }

  Widget _buildDateChip(int index, String label, String sub) {
    final isSelected = _selectedDateIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedDateIndex = index),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryContainer : AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: AppTypography.labelSm.copyWith(
                  color: isSelected ? Colors.white70 : AppColors.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                sub,
                style: AppTypography.labelSm.copyWith(
                  color: isSelected ? Colors.white : AppColors.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16),
      ),
    );
  }


  Widget _buildQuickFare(String label, String value) {
    final isSelected = _fareController.text == value;
    return InkWell(
      onTap: () => setState(() => _fareController.text = value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryContainer : AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: AppTypography.labelMd.copyWith(
            color: isSelected ? Colors.white : AppColors.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
