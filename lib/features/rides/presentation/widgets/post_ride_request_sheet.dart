import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';

class PostRideRequestSheet extends ConsumerStatefulWidget {
  const PostRideRequestSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PostRideRequestSheet(),
    );
  }

  @override
  ConsumerState<PostRideRequestSheet> createState() => _PostRideRequestSheetState();
}

class _PostRideRequestSheetState extends ConsumerState<PostRideRequestSheet> {
  final _pickupController = TextEditingController(text: 'DIU Smart City, Ashulia');
  final _dropoffController = TextEditingController();
  final _notesController = TextEditingController();
  double _proposedFare = 50.0;
  String _selectedTime = 'Right Now (Next 15m)';
  bool _isLoading = false;

  final List<String> _quickDestinations = [
    'Uttara Sector 11',
    'Uttara House Building',
    'Mirpur 10 Circle',
    'Dhanmondi 27',
    'Birulia Bridge',
    'Ashulia Bus Stand',
  ];

  final List<String> _quickTimes = [
    'Right Now (Next 15m)',
    'Post-Class (2:30 PM)',
    'Evening (5:00 PM)',
    'Tomorrow Morning',
  ];

  @override
  void dispose() {
    _pickupController.dispose();
    _dropoffController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    final dropoff = _dropoffController.text.trim();
    if (dropoff.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter or select a destination!')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = ref.read(authNotifierProvider).user;
      final ridesRepo = ref.read(ridesRepositoryProvider);

      await ridesRepo.createPassengerRequest(
        passengerId: user?.id ?? 'usr_student',
        passengerName: user?.name ?? 'DIU Student',
        passengerPhone: user?.phone ?? '01712345678',
        pickup: _pickupController.text.trim(),
        dropoff: dropoff,
        requestedTime: _selectedTime,
        proposedFare: _proposedFare,
        notes: _notesController.text.trim(),
      );

      if (!mounted) return;
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF1C1C1E),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Color(0xFF34C759), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Ride Request Broadcasted! Campus riders heading to $dropoff will be notified.',
                  style: AppTypography.labelMd.copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error posting request: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag indicator
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Request a Bike Ride',
                      style: AppTypography.headlineSm.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF141416),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Broadcast your destination to peer riders',
                      style: AppTypography.labelSm.copyWith(color: const Color(0xFF8E8E93)),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.two_wheeler, size: 14, color: Color(0xFFE65100)),
                      SizedBox(width: 4),
                      Text(
                        '1 Passenger',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFE65100),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Pickup Input
            Text(
              'PICKUP LOCATION',
              style: AppTypography.labelSm.copyWith(
                fontWeight: FontWeight.bold,
                color: const Color(0xFF8E8E93),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF4F5F7),
                borderRadius: BorderRadius.circular(14),
              ),
              child: TextField(
                controller: _pickupController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.trip_origin, size: 18, color: Color(0xFF2E7D32)),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Dropoff Input
            Text(
              'WHERE DO YOU WANT TO GO?',
              style: AppTypography.labelSm.copyWith(
                fontWeight: FontWeight.bold,
                color: const Color(0xFF8E8E93),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF2F2F7),
                borderRadius: BorderRadius.circular(14),
              ),
              child: TextField(
                controller: _dropoffController,
                decoration: const InputDecoration(
                  hintText: 'e.g. Uttara Sector 11, Mirpur 10...',
                  prefixIcon: Icon(Icons.location_on, size: 20, color: Color(0xFF34C759)),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Quick Hubs
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _quickDestinations.map((dest) {
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _dropoffController.text = dest;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black.withOpacity(0.08)),
                    ),
                    child: Text(
                      dest,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Preferred Departure Time
            Text(
              'PREFERRED TIME',
              style: AppTypography.labelSm.copyWith(
                fontWeight: FontWeight.bold,
                color: const Color(0xFF8E8E93),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _quickTimes.map((t) {
                final isSelected = _selectedTime == t;
                return GestureDetector(
                  onTap: () => setState(() => _selectedTime = t),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      t,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white : const Color(0xFF3A3A3C),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Proposed Fuel Share Fare
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'PROPOSED FUEL CONTRIBUTION',
                  style: AppTypography.labelSm.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF8E8E93),
                    fontSize: 11,
                  ),
                ),
                Text(
                  '৳${_proposedFare.toInt()}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFE65100),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [40.0, 50.0, 60.0, 75.0, 90.0].map((f) {
                final isSel = _proposedFare == f;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _proposedFare = f),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isSel ? const Color(0xFFE65100) : const Color(0xFFF4F5F7),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '৳${f.toInt()}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isSel ? Colors.white : const Color(0xFF3A3A3C),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 22),

            // Submit Button (Obsidian Dark Button Matching Reference 2)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submitRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF141416),
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.send_rounded, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Post Request (৳${_proposedFare.toInt()})',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
