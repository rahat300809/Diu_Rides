import 'package:flutter/material.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/core/utils/currency_formatter.dart';
import 'package:diu_ride/core/utils/date_time_utils.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';
import 'package:diu_ride/features/rides/data/models/vehicle_model.dart';

class RideResultCard extends StatelessWidget {
  final RideModel ride;
  final VoidCallback onBook;
  final VoidCallback onTapDetails;

  const RideResultCard({
    super.key,
    required this.ride,
    required this.onBook,
    required this.onTapDetails,
  });

  @override
  Widget build(BuildContext context) {
    final isBike = ride.vehicle.type == VehicleType.bike;
    final primaryColor = isBike ? AppColors.primary : AppColors.secondary;
    final arrivalTime = ride.departureTime.add(Duration(minutes: ride.durationMinutes));

    return InkWell(
      onTap: onTapDetails,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: AppColors.cardShadow,
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top driver profile row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: AppColors.surfaceContainerHigh,
                          child: Text(
                            ride.driverName.substring(0, 1),
                            style: AppTypography.headlineSm.copyWith(color: AppColors.primary),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.check, size: 10, color: Colors.white),
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
                            children: [
                              Text(
                                ride.driverName,
                                style: AppTypography.headlineSm.copyWith(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                ride.driverDept,
                                style: AppTypography.labelSm.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text('•', style: AppTypography.labelSm),
                              const SizedBox(width: 6),
                              const Icon(Icons.star, size: 14, color: AppColors.ratingStar),
                              const SizedBox(width: 2),
                              Text(
                                ride.driverRating.toStringAsFixed(1),
                                style: AppTypography.labelSm.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.onSurface,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '(${ride.driverRideCount})',
                                style: AppTypography.labelSm.copyWith(
                                  color: AppColors.outline,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Vehicle & Safety feature banner
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.two_wheeler,
                            size: 16,
                            color: primaryColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            ride.vehicle.modelName,
                            style: AppTypography.bodyMdMedium.copyWith(fontSize: 12.5),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Icon(
                            Icons.verified,
                            size: 14,
                            color: primaryColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'DIU Verified Bike',
                            style: AppTypography.labelSm.copyWith(
                              color: primaryColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Route Timetable & Visual Progress Bar
                Row(
                  children: [
                    // Origin
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateTimeUtils.formatTime(ride.departureTime),
                          style: AppTypography.headlineSm.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(
                          width: 100,
                          child: Text(
                            ride.originName,
                            style: AppTypography.labelSm.copyWith(
                              color: AppColors.onSurfaceVariant,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),

                    // Center Distance / Duration Graphic
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Column(
                          children: [
                            Text(
                              '${ride.durationMinutes} mins • ${ride.distanceKm.toStringAsFixed(0)} km',
                              style: AppTypography.labelSm.copyWith(
                                color: primaryColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 10.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    height: 2,
                                    color: primaryColor,
                                  ),
                                ),
                                Icon(Icons.arrow_forward, size: 14, color: primaryColor),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              ride.routeCorridor,
                              style: AppTypography.labelSm.copyWith(
                                color: AppColors.outline,
                                fontSize: 9.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Destination
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          DateTimeUtils.formatTime(arrivalTime),
                          style: AppTypography.headlineSm.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(
                          width: 110,
                          child: Text(
                            ride.destinationName,
                            style: AppTypography.labelSm.copyWith(
                              color: AppColors.onSurfaceVariant,
                              fontSize: 11,
                            ),
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Price & Instant Book CTA
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              CurrencyFormatter.formatBdt(ride.farePerSeat),
                              style: AppTypography.headlineLg.copyWith(
                                color: primaryColor,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '/ student',
                              style: AppTypography.labelSm.copyWith(
                                color: AppColors.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: AppColors.error,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Only ${ride.availableSeats} seat left',
                              style: AppTypography.labelSm.copyWith(
                                color: AppColors.error,
                                fontWeight: FontWeight.w600,
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    // CTA Button
                    ElevatedButton.icon(
                      onPressed: onBook,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: AppColors.onPrimary,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      icon: const Icon(Icons.bolt, size: 16),
                      label: Text(
                        'Instant Book',
                        style: AppTypography.labelLg.copyWith(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Top-right match tag
            if (isBike)
              Positioned(
                top: -8,
                right: -8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: const BoxDecoration(
                    color: AppColors.primaryFixed,
                    borderRadius: BorderRadius.only(
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(10),
                    ),
                  ),
                  child: Text(
                    'FASTEST MATCH',
                    style: AppTypography.labelSm.copyWith(
                      color: AppColors.onPrimaryFixed,
                      fontWeight: FontWeight.bold,
                      fontSize: 8.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
