import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/core/utils/currency_formatter.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';
import 'package:diu_ride/features/booking/presentation/providers/booking_provider.dart';
import 'package:diu_ride/features/chat/presentation/screens/chat_screen.dart';

class BookingConfirmationSheet extends ConsumerStatefulWidget {
  final RideModel ride;
  final VoidCallback onBookingSuccess;

  const BookingConfirmationSheet({
    super.key,
    required this.ride,
    required this.onBookingSuccess,
  });

  static Future<void> show({
    required BuildContext context,
    required RideModel ride,
    required VoidCallback onBookingSuccess,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => BookingConfirmationSheet(
        ride: ride,
        onBookingSuccess: onBookingSuccess,
      ),
    );
  }

  @override
  ConsumerState<BookingConfirmationSheet> createState() =>
      _BookingConfirmationSheetState();
}

class _BookingConfirmationSheetState
    extends ConsumerState<BookingConfirmationSheet> {
  int _seats = 1;
  String? _selectedDropoffPoint;

  @override
  void initState() {
    super.initState();
    _selectedDropoffPoint = widget.ride.destinationName;
  }

  void _confirmBooking() async {
    final total = widget.ride.farePerSeat * _seats;
    final dropoff = _selectedDropoffPoint ?? widget.ride.destinationName;
    final success = await ref.read(bookingNotifierProvider.notifier).bookSeat(
          rideId: widget.ride.id,
          pickupPoint: widget.ride.originName,
          dropoffPoint: dropoff,
          seatsBooked: _seats,
          totalFare: total,
          ride: widget.ride, // pass ride so driver name is in notification
        );

    if (mounted) {
      Navigator.of(context).pop();
      if (success) {
        widget.onBookingSuccess();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              rideId: widget.ride.id,
              driverName: widget.ride.driverName,
              peerName: widget.ride.driverName,
              vehicleModel: widget.ride.vehicle.modelName,
              peerPhone: widget.ride.driverPhone,
              peerRole: 'Driver',
            ),
          ),
        );
      } else {
        final err =
            ref.read(bookingNotifierProvider).errorMessage ?? 'Booking failed';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            content: Text(err),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookingState = ref.watch(bookingNotifierProvider);
    final totalFare = widget.ride.farePerSeat * _seats;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Driver header
          Row(
            children: [
              // Avatar
              Container(
                width: 50,
                height: 50,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [AppColors.primaryContainer, AppColors.primary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: Text(
                    widget.ride.driverName.isNotEmpty
                        ? widget.ride.driverName[0].toUpperCase()
                        : 'D',
                    style: AppTypography.headlineSm
                        .copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.ride.driverName,
                            style: AppTypography.bodyLgMedium
                                .copyWith(fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.verified, size: 15, color: AppColors.primary),
                      ],
                    ),
                    Text(
                      '${widget.ride.driverDept} • ⭐ ${widget.ride.driverRating.toStringAsFixed(1)}',
                      style: AppTypography.labelSm
                          .copyWith(color: AppColors.onSurfaceVariant),
                    ),
                    Text(
                      widget.ride.vehicle.modelName,
                      style: AppTypography.labelSm.copyWith(color: AppColors.outline),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyFormatter.formatBdt(widget.ride.farePerSeat),
                    style: AppTypography.headlineSm.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text('/ seat', style: AppTypography.labelSm),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Route card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.outlineVariant.withOpacity(0.5)),
            ),
            child: Column(
              children: [
                _buildRouteRow(
                  icon: Icons.trip_origin,
                  color: AppColors.primary,
                  text: widget.ride.originName,
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 7),
                  child: Row(
                    children: [
                      Container(
                        width: 2,
                        height: 20,
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.outlineVariant,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildRouteRow(
                  icon: Icons.location_on,
                  color: AppColors.error,
                  text: _selectedDropoffPoint ?? widget.ride.destinationName,
                ),
                if (widget.ride.destinationChoices.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Choose Your Specific Destination Stop:',
                      style: AppTypography.labelSm.copyWith(
                        color: AppColors.secondary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: {
                        widget.ride.destinationName,
                        ...widget.ride.destinationChoices,
                      }.map((choice) {
                        final isSelected = (_selectedDropoffPoint ?? widget.ride.destinationName) == choice;
                        return ChoiceChip(
                          label: Text(choice),
                          selected: isSelected,
                          onSelected: (_) {
                            setState(() => _selectedDropoffPoint = choice);
                          },
                          selectedColor: AppColors.primaryContainer,
                          labelStyle: TextStyle(
                            fontSize: 12,
                            color: isSelected ? AppColors.onPrimaryContainer : AppColors.onSurface,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ETA + available seats info strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primaryFixed.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildInfoChip(
                  Icons.access_time_outlined,
                  '${widget.ride.durationMinutes} min',
                  'Est. Duration',
                ),
                Container(
                  width: 1,
                  height: 28,
                  color: AppColors.outlineVariant,
                ),
                _buildInfoChip(
                  Icons.route,
                  '${widget.ride.distanceKm.toStringAsFixed(1)} km',
                  'Distance',
                ),
                Container(
                  width: 1,
                  height: 28,
                  color: AppColors.outlineVariant,
                ),
                _buildInfoChip(
                  Icons.event_seat_outlined,
                  '${widget.ride.availableSeats} left',
                  'Seats',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Seat selector
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Seats to Book', style: AppTypography.bodyLgMedium),
                  Text(
                    '${widget.ride.availableSeats} spots available',
                    style: AppTypography.labelSm.copyWith(color: AppColors.outline),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Row(
                  children: [
                    _stepButton(
                      Icons.remove,
                      _seats > 1 ? () => setState(() => _seats--) : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$_seats',
                      style: AppTypography.headlineSm
                          .copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    _stepButton(
                      Icons.add,
                      _seats < widget.ride.availableSeats
                          ? () => setState(() => _seats++)
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Total
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primaryFixed.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total Cost Share', style: AppTypography.bodyLgMedium),
                Text(
                  CurrencyFormatter.formatBdt(totalFare),
                  style: AppTypography.headlineMd.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Uber-style policy note
          Row(
            children: [
              const Icon(Icons.info_outline, size: 14, color: AppColors.outline),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Driver will be notified and must accept. Your seat is held for 5 minutes.',
                  style: AppTypography.labelSm
                      .copyWith(color: AppColors.outline, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // CTA Button
          ElevatedButton(
            onPressed: bookingState.isLoading ? null : _confirmBooking,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              elevation: 0,
            ),
            child: bookingState.isLoading
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Sending request…',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.notifications_active, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Request Seat • ${CurrencyFormatter.formatBdt(totalFare)}',
                        style: AppTypography.labelLg
                            .copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteRow({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: AppTypography.bodyMdMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoChip(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTypography.labelLg
              .copyWith(fontWeight: FontWeight.bold, fontSize: 12),
        ),
        Text(
          label,
          style:
              AppTypography.labelSm.copyWith(color: AppColors.outline, fontSize: 10),
        ),
      ],
    );
  }

  Widget _stepButton(IconData icon, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: onTap != null
              ? AppColors.primaryContainer
              : AppColors.surfaceContainerHigh,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 16,
          color: onTap != null ? Colors.white : AppColors.outline,
        ),
      ),
    );
  }
}
