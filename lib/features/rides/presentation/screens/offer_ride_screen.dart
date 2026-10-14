import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/constants/campus_locations.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/notifications/presentation/providers/notifications_provider.dart';
import 'package:diu_ride/features/rides/data/models/vehicle_model.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';
import 'package:diu_ride/features/tracking/presentation/screens/ride_details_tracking_screen.dart';
import 'package:diu_ride/features/chat/presentation/screens/chat_screen.dart';
import 'package:diu_ride/features/rides/data/models/passenger_request_model.dart';
import 'package:diu_ride/core/utils/date_time_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:diu_ride/features/profile/presentation/widgets/motorcycle_config_dialog.dart';

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
  final _bikeModelController = TextEditingController(text: 'Yamaha FZ-X');
  final _licensePlateController = TextEditingController(text: 'Dhaka Metro-HA 24-8891');
  final _bikeColorController = TextEditingController(text: 'Black Metallic');
  final _manualDateController = TextEditingController();
  final _manualTimeController = TextEditingController();
  final List<TextEditingController> _extraDestinationControllers = [];

  bool _isWaypointOpen = false;
  int _selectedDateIndex = 0; // 0: Today, 1: Tomorrow, 2: Custom
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _departureTime = const TimeOfDay(hour: 16, minute: 30);
  final VehicleType _vehicleType = VehicleType.bike; // Strictly motorbikes only
  final int _seats = 1; // 1 passenger seat for bikes
  String _bikeModel = 'Yamaha FZ-X';
  bool _hasPassengerHelmet = true;
  final bool _isFemaleOnly = false;
  bool _isPublishing = false;
  bool _isManualScheduleInput = false;

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
  void initState() {
    super.initState();
    _manualDateController.text = '${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}';
    _manualTimeController.text = '04:30 PM';
    _loadSavedMotoConfig();
  }

  Future<void> _loadSavedMotoConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final model = prefs.getString('rider_moto_model');
      final plate = prefs.getString('rider_moto_plate');
      final color = prefs.getString('rider_moto_color');
      final helmet = prefs.getBool('rider_moto_helmet');

      if (model != null && model.isNotEmpty) {
        _bikeModelController.text = model;
        _bikeModel = model;
      }
      if (plate != null && plate.isNotEmpty) {
        _licensePlateController.text = plate;
      }
      if (color != null && color.isNotEmpty) {
        _bikeColorController.text = color;
      }
      if (helmet != null) {
        _hasPassengerHelmet = helmet;
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _originController.dispose();
    _destinationController.dispose();
    _waypointController.dispose();
    _fareController.dispose();
    _bikeModelController.dispose();
    _licensePlateController.dispose();
    _bikeColorController.dispose();
    _manualDateController.dispose();
    _manualTimeController.dispose();
    for (final c in _extraDestinationControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _adjustTime(int deltaMinutes) {
    int totalMinutes = _departureTime.hour * 60 + _departureTime.minute + deltaMinutes;
    if (totalMinutes < 0) totalMinutes += 1440;
    if (totalMinutes >= 1440) totalMinutes -= 1440;
    setState(() {
      _departureTime = TimeOfDay(hour: totalMinutes ~/ 60, minute: totalMinutes % 60);
      final hour = _departureTime.hourOfPeriod == 0 ? 12 : _departureTime.hourOfPeriod;
      final minute = _departureTime.minute.toString().padLeft(2, '0');
      final period = _departureTime.period == DayPeriod.am ? 'AM' : 'PM';
      _manualTimeController.text = '${hour.toString().padLeft(2, '0')}:$minute $period';
    });
  }

  Future<void> _pickCustomDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 60)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFE65100),
              onPrimary: Colors.white,
              onSurface: Color(0xFF1C1C1E),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _selectedDateIndex = 2;
        _manualDateController.text = '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
      });
    }
  }

  Future<void> _pickCustomTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _departureTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFE65100),
              onPrimary: Colors.white,
              onSurface: Color(0xFF1C1C1E),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _departureTime = picked;
        final hour = picked.hourOfPeriod == 0 ? 12 : picked.hourOfPeriod;
        final minute = picked.minute.toString().padLeft(2, '0');
        final period = picked.period == DayPeriod.am ? 'AM' : 'PM';
        _manualTimeController.text = '${hour.toString().padLeft(2, '0')}:$minute $period';
      });
    }
  }

  void _publishRide() async {
    final origin = _originController.text.trim();
    final dest = _destinationController.text.trim();
    final fare = double.tryParse(_fareController.text.trim()) ?? 50.0;
    final bikeName = _bikeModelController.text.trim().isNotEmpty
        ? _bikeModelController.text.trim()
        : _bikeModel;
    final plate = _licensePlateController.text.trim().isNotEmpty
        ? _licensePlateController.text.trim()
        : 'Dhaka Metro';
    final color = _bikeColorController.text.trim().isNotEmpty
        ? _bikeColorController.text.trim()
        : 'Black';

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
      modelName: bikeName,
      color: color,
      licensePlate: plate,
      hasAc: false,
      hasPassengerHelmet: _hasPassengerHelmet,
      isSmokeFree: true,
      hasPhoneCharger: true,
      hasLuggageSpace: false,
    );

    // Support manual schedule text if provided
    DateTime departureDateTime;
    try {
      if (_isManualScheduleInput && _manualDateController.text.trim().isNotEmpty) {
        final parts = _manualDateController.text.trim().split(RegExp(r'[/.-]'));
        if (parts.length == 3) {
          final d = int.parse(parts[0]);
          final m = int.parse(parts[1]);
          final y = int.parse(parts[2].length == 2 ? '20${parts[2]}' : parts[2]);
          _selectedDate = DateTime(y, m, d);
        }
      }
      departureDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _departureTime.hour,
        _departureTime.minute,
      );
    } catch (_) {
      departureDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _departureTime.hour,
        _departureTime.minute,
      );
    }

    final allDestChoices = <String>[dest];
    for (final c in _extraDestinationControllers) {
      final t = c.text.trim();
      if (t.isNotEmpty && !allDestChoices.contains(t)) {
        allDestChoices.add(t);
      }
    }

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
          destinationChoices: allDestChoices,
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
      ref.invalidate(allSystemRidesProvider);
      ref.invalidate(departingSoonRidesProvider);
      ref.invalidate(searchRidesResultsProvider);
      ref.invalidate(allAvailableRidesProvider);

      // Notify the POSTER that their ride is now live
      ref.read(notificationsProvider.notifier).onRidePublishedByMe(
        rideId: 'ride_${DateTime.now().millisecondsSinceEpoch}',
        origin: origin,
        destination: dest,
        departureTime: departureDateTime,
        fare: fare,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFE65100),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Ride Published! Visible to all DIU students ✓',
                  style: AppTypography.bodyMdMedium.copyWith(color: Colors.white),
                ),
              ),
            ],
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
                          'Driver: ${ref.read(authNotifierProvider).user?.name ?? 'You'}',
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

                    // Multi-Choice Drop-off Stops
                    if (_extraDestinationControllers.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text('Alternative Drop-off Choices', 
                        style: AppTypography.labelSm.copyWith(color: AppColors.secondary, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      for (int i = 0; i < _extraDestinationControllers.length; i++) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _extraDestinationControllers[i],
                                  decoration: InputDecoration(
                                    prefixIcon: const Icon(Icons.alt_route, color: AppColors.secondary, size: 20),
                                    hintText: 'Drop-off stop #${i + 2} (e.g. Farmgate, Mirpur 10)...',
                                    labelText: 'Drop-off Choice #${i + 2}',
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                icon: const Icon(Icons.cancel_outlined, color: AppColors.error),
                                tooltip: 'Remove this stop',
                                onPressed: () {
                                  setState(() {
                                    _extraDestinationControllers[i].dispose();
                                    _extraDestinationControllers.removeAt(i);
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () {
                        setState(() {
                          _extraDestinationControllers.add(TextEditingController());
                        });
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.secondary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.secondary.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.add_location_alt_outlined, size: 16, color: AppColors.secondary),
                            const SizedBox(width: 6),
                            Text(
                              '+ Add Multiple Choice of Destination / Drop-off Stop',
                              style: AppTypography.labelSm.copyWith(
                                color: AppColors.secondary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
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
                extraTag: 'Campus Commute',
                extraAction: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _isManualScheduleInput = !_isManualScheduleInput;
                    });
                  },
                  icon: Icon(
                    _isManualScheduleInput ? Icons.tune : Icons.edit_calendar,
                    size: 16,
                    color: const Color(0xFFE65100),
                  ),
                  label: Text(
                    _isManualScheduleInput ? 'Quick Stepper' : 'Manual Input',
                    style: AppTypography.labelSm.copyWith(
                      color: const Color(0xFFE65100),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Date selector chips
                    Row(
                      children: [
                        _buildDateChip(0, 'Today', '${DateTime.now().day}/${DateTime.now().month}'),
                        const SizedBox(width: 8),
                        _buildDateChip(1, 'Tomorrow', '${DateTime.now().add(const Duration(days: 1)).day}/${DateTime.now().add(const Duration(days: 1)).month}'),
                        const SizedBox(width: 8),
                        _buildDateChip(2, 'Custom', _selectedDateIndex == 2 ? '${_selectedDate.day}/${_selectedDate.month}' : 'Pick Date'),
                      ],
                    ),
                    const SizedBox(height: 14),

                    if (_isManualScheduleInput) ...[
                      // Manual Input Fields for Date and Time
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF8F3),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFFFD180)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Customized Schedule Input',
                              style: AppTypography.labelSm.copyWith(
                                color: const Color(0xFFE65100),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _manualDateController,
                                    decoration: InputDecoration(
                                      labelText: 'Date (DD/MM/YYYY)',
                                      labelStyle: const TextStyle(fontSize: 12),
                                      hintText: '28/04/2026',
                                      prefixIcon: const Icon(Icons.calendar_today, size: 18, color: Color(0xFFE65100)),
                                      suffixIcon: IconButton(
                                        icon: const Icon(Icons.event, size: 18, color: Color(0xFFE65100)),
                                        onPressed: _pickCustomDate,
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _manualTimeController,
                                    decoration: InputDecoration(
                                      labelText: 'Departure Time',
                                      labelStyle: const TextStyle(fontSize: 12),
                                      hintText: '04:30 PM',
                                      prefixIcon: const Icon(Icons.access_time, size: 18, color: Color(0xFFE65100)),
                                      suffixIcon: IconButton(
                                        icon: const Icon(Icons.watch_later_outlined, size: 18, color: Color(0xFFE65100)),
                                        onPressed: _pickCustomTime,
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
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
                            InkWell(
                              onTap: _pickCustomTime,
                              borderRadius: BorderRadius.circular(8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text('Departure Time', style: AppTypography.labelSm),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.edit, size: 13, color: Color(0xFFE65100)),
                                    ],
                                  ),
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
                                      Text('(Tap to pick)', style: AppTypography.labelSm.copyWith(color: AppColors.outline)),
                                    ],
                                  ),
                                ],
                              ),
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
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // STEP 3: MOTORBIKE & HELMET CARD
              _buildSectionCard(
                stepNum: '3',
                title: 'Motorbike & Safety',
                extraTag: '1 Passenger Seat',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Customizable Bike Model Name
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Customize Motorcycle Name', style: AppTypography.labelSm),
                        InkWell(
                          onTap: () {
                            MotorcycleConfigDialog.show(
                              context: context,
                              onSaved: (m, p, c, h) {
                                setState(() {
                                  _bikeModelController.text = m;
                                  _bikeModel = m;
                                  _licensePlateController.text = p;
                                  _bikeColorController.text = c;
                                  _hasPassengerHelmet = h;
                                });
                              },
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF3E0),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.settings, size: 13, color: Color(0xFFE65100)),
                                SizedBox(width: 4),
                                Text(
                                  'Moto Setup ⚙️',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFE65100),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _bikeModelController,
                      onChanged: (val) {
                        setState(() {
                          _bikeModel = val.trim().isNotEmpty ? val.trim() : 'Motorbike';
                        });
                      },
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.two_wheeler, color: Color(0xFFE65100)),
                        hintText: 'e.g. Yamaha FZ-X, Suzuki Gixxer, Honda Hornet',
                        labelText: 'Motorcycle Model Name',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Quick Preset Chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: _availableBikes.map((bike) {
                          final isSelected = _bikeModelController.text == bike;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ActionChip(
                              label: Text(bike),
                              labelStyle: TextStyle(
                                fontSize: 11,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected ? Colors.white : const Color(0xFF1C1C1E),
                              ),
                              backgroundColor: isSelected ? const Color(0xFFE65100) : const Color(0xFFF2F2F7),
                              side: BorderSide.none,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              onPressed: () {
                                setState(() {
                                  _bikeModelController.text = bike;
                                  _bikeModel = bike;
                                });
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // License Plate and Color Row
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _licensePlateController,
                            decoration: InputDecoration(
                              labelText: 'License Plate',
                              hintText: 'Dhaka Metro-HA 24-8891',
                              labelStyle: const TextStyle(fontSize: 12),
                              prefixIcon: const Icon(Icons.pin, size: 18, color: Color(0xFFE65100)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _bikeColorController,
                            decoration: InputDecoration(
                              labelText: 'Color',
                              hintText: 'Black Metallic',
                              labelStyle: const TextStyle(fontSize: 12),
                              prefixIcon: const Icon(Icons.color_lens_outlined, size: 18, color: Color(0xFFE65100)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
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
                  backgroundColor: const Color(0xFFE65100),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 4,
                  shadowColor: const Color(0x40E65100),
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
                          const Icon(Icons.two_wheeler, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            'Publish Campus Ride (৳${_fareController.text}/seat)',
                            style: AppTypography.labelLg.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
              ),

              const SizedBox(height: 24),

              // MY ACTIVE RIDES & STUDENT REQUESTS SUB-SECTION
              _buildMyActiveRidesSection(),

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
        onTap: () async {
          if (index == 2) {
            await _pickCustomDate();
          } else {
            setState(() {
              _selectedDateIndex = index;
              _selectedDate = index == 0 ? DateTime.now() : DateTime.now().add(const Duration(days: 1));
              _manualDateController.text = '${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.year}';
            });
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFE65100) : AppColors.surfaceContainer,
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

  Widget _buildMyActiveRidesSection() {
    final user = ref.watch(authNotifierProvider).user;
    final allRides = ref.watch(allSystemRidesProvider).value ?? [];
    final myRides = allRides.where((r) =>
      user != null && (
        r.driverId == user.id ||
        r.driverId == user.studentId ||
        (user.phone.isNotEmpty && r.driverPhone == user.phone)
      )
    ).toList();
    final passengerReqsAsync = ref.watch(passengerRequestsProvider);
    final ridesRepo = ref.read(ridesRepositoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Divider with label
        Row(
          children: [
            const Expanded(child: Divider(color: Color(0xFFE5E7EB))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'LIVE COMMUTE ACTIVITY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: Colors.grey[600],
                ),
              ),
            ),
            const Expanded(child: Divider(color: Color(0xFFE5E7EB))),
          ],
        ),
        const SizedBox(height: 18),

        // SECTION 1: My Active Posted Rides
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
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
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.two_wheeler, color: Color(0xFFE65100), size: 18),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'My Posted Rides',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF141416),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: myRides.isNotEmpty ? const Color(0xFFE8F5E9) : const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      myRides.isNotEmpty ? '${myRides.length} Active' : 'None active',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: myRides.isNotEmpty ? const Color(0xFF2E7D32) : Colors.grey,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (myRides.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FA),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 16, color: Color(0xFF8E8E93)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'You haven\'t published any rides yet. Fill details above and tap Publish.',
                          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...myRides.map((ride) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FA),
                    borderRadius: BorderRadius.circular(14),
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
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF34C759),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'LIVE • Visible to DIU Students',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2E7D32),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '৳${ride.farePerSeat.toInt()}/seat',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFE65100),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${ride.originName} → ${ride.destinationName}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF141416),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Leaves: ${DateTimeUtils.formatTime(ride.departureTime)}',
                            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                          ),
                          Row(
                            children: [
                              InkWell(
                                onTap: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                      title: const Text('Delete Ride Post?'),
                                      content: Text('Are you sure you want to delete this ride offer from ${ride.originName} to ${ride.destinationName}?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx, false),
                                          child: const Text('Cancel'),
                                        ),
                                        ElevatedButton(
                                          onPressed: () => Navigator.pop(ctx, true),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFFD32F2F),
                                            foregroundColor: Colors.white,
                                          ),
                                          child: const Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    await ridesRepo.deleteRide(ride.id);
                                    ref.invalidate(allAvailableRidesProvider);
                                    ref.invalidate(departingSoonRidesProvider);
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Ride post removed successfully.'),
                                        backgroundColor: Color(0xFFD32F2F),
                                      ),
                                    );
                                    setState(() {});
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFEBEE),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFFFCDD2)),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.delete_outline, size: 13, color: Color(0xFFD32F2F)),
                                      SizedBox(width: 3),
                                      Text(
                                        'Delete',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFFD32F2F),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => RideDetailsTrackingScreen(rideId: ride.id),
                                    ),
                                  );
                                },
                                child: const Text(
                                  'Track / Manage →',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFE65100),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                )),
            ],
          ),
        ),

        const SizedBox(height: 18),

        // SECTION 2: Student Requests (Looking for Bikers)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
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
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE3F2FD),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.hail, color: Color(0xFF1976D2), size: 18),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Student Ride Requests',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF141416),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE3F2FD),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Looking for Bikers',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1976D2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Passengers requesting rides. You can accept to ride together.',
                style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
              ),
              const SizedBox(height: 14),

              passengerReqsAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE65100)),
                  ),
                ),
                error: (e, _) => Text('Could not load requests: $e', style: const TextStyle(fontSize: 12)),
                data: (rawList) {
                  final reqList = rawList.map((e) {
                    if (e is PassengerRequestModel) return e;
                    return PassengerRequestModel.fromJson(Map<String, dynamic>.from(e as Map));
                  }).toList();

                  if (reqList.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F9FA),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_outline, size: 16, color: Color(0xFF8E8E93)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'No open student requests right now. New requests will appear here.',
                              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return Column(
                    children: reqList.map((req) {
                      final isAccepted = req.isAccepted;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FA),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isAccepted ? const Color(0xFFC8E6C9) : const Color(0xFFE5E7EB),
                          ),
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
                                    const SizedBox(width: 7),
                                    Text(
                                      req.passengerName,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '(${req.passengerDept})',
                                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
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
                                    'Offered: ৳${req.proposedFare.toInt()}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFE65100),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.place, size: 14, color: Color(0xFFE65100)),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '${req.pickup} → ${req.dropoff}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Time: ${req.requestedTime}',
                              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 10),
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
                                            ),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.chat, size: 14),
                                      label: const Text('Chat with Passenger', style: TextStyle(fontSize: 12)),
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

                                        if (!mounted) return;
                                        if (ok) {
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
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                      icon: const Icon(Icons.check, size: 14),
                                      label: const Text('Accept & Ride', style: TextStyle(fontSize: 12)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFE65100),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => ChatScreen(
                                            rideId: req.id,
                                            peerName: req.passengerName,
                                            vehicleModel: 'Motorbike Commute',
                                            peerPhone: req.passengerPhone,
                                            peerRole: 'Passenger',
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.chat_bubble_outline, size: 14),
                                    label: const Text('Chat', style: TextStyle(fontSize: 12)),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFFE65100),
                                      side: const BorderSide(color: Color(0xFFE65100)),
                                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  InkWell(
                                    onTap: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                          title: const Text('Delete Student Request?'),
                                          content: Text('Are you sure you want to remove this request from ${req.passengerName} (${req.pickup} → ${req.dropoff})?'),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(ctx, false),
                                              child: const Text('Cancel'),
                                            ),
                                            ElevatedButton(
                                              onPressed: () => Navigator.pop(ctx, true),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(0xFFD32F2F),
                                                foregroundColor: Colors.white,
                                              ),
                                              child: const Text('Delete'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        await ridesRepo.deletePassengerRequest(req.id);
                                        ref.invalidate(passengerRequestsProvider);
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Student request removed.'),
                                            backgroundColor: Color(0xFFD32F2F),
                                          ),
                                        );
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFEBEE),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: const Color(0xFFFFCDD2)),
                                      ),
                                      child: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFD32F2F)),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
