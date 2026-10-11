import 'package:flutter/material.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/features/rides/data/models/vehicle_model.dart';

class CampusCategoryGrid extends StatelessWidget {
  final VehicleType? selectedType;
  final bool femaleOnlySelected;
  final Function(VehicleType? type, bool isFemaleOnly) onSelectCategory;

  const CampusCategoryGrid({
    super.key,
    required this.selectedType,
    required this.femaleOnlySelected,
    required this.onSelectCategory,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Campus Rides',
                style: AppTypography.headlineSm.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
              ),
              InkWell(
                onTap: () {
                  _showGuidelinesSheet(context);
                },
                child: Text(
                  'View Guidelines',
                  style: AppTypography.labelSm.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2x2 Grid of Categories
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.45,
            children: [
              // 1. Bike Share
              _buildCategoryCard(
                title: 'Bike Share',
                subtitle: '1 seat • Avg ৳35',
                badgeText: 'Fastest',
                badgeBg: AppColors.primaryFixed.withOpacity(0.4),
                badgeColor: AppColors.primary,
                icon: Icons.two_wheeler,
                iconColor: AppColors.primary,
                iconBg: AppColors.primary.withOpacity(0.1),
                isSelected: selectedType == VehicleType.bike && !femaleOnlySelected,
                onTap: () => onSelectCategory(VehicleType.bike, false),
              ),

              // 2. Student Carpool
              _buildCategoryCard(
                title: 'Student Carpool',
                subtitle: '3 seats • Avg ৳70',
                badgeText: 'AC Comfort',
                badgeBg: AppColors.secondaryFixed,
                badgeColor: AppColors.onSecondaryFixed,
                icon: Icons.directions_car,
                iconColor: AppColors.secondary,
                iconBg: AppColors.secondary.withOpacity(0.1),
                isSelected: selectedType == VehicleType.car && !femaleOnlySelected,
                onTap: () => onSelectCategory(VehicleType.car, false),
              ),

              // 3. Micro Shuttle
              _buildCategoryCard(
                title: 'Micro Shuttle',
                subtitle: '8 seats • Avg ৳50',
                badgeText: 'Fixed Route',
                badgeBg: AppColors.surfaceContainerHigh,
                badgeColor: AppColors.onSurface,
                icon: Icons.airport_shuttle,
                iconColor: AppColors.tertiary,
                iconBg: AppColors.tertiary.withOpacity(0.1),
                isSelected: selectedType == VehicleType.microbus && !femaleOnlySelected,
                onTap: () => onSelectCategory(VehicleType.microbus, false),
              ),

              // 4. Female-Only Ride
              _buildCategoryCard(
                title: 'Female-Only Ride',
                subtitle: 'Verified female peers',
                badgeText: 'Women Safe',
                badgeBg: AppColors.primaryFixed,
                badgeColor: AppColors.onPrimaryFixed,
                icon: Icons.female,
                iconColor: AppColors.primaryContainer,
                iconBg: AppColors.primaryContainer.withOpacity(0.1),
                isSelected: femaleOnlySelected,
                onTap: () => onSelectCategory(null, true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard({
    required String title,
    required String subtitle,
    required String badgeText,
    required Color badgeBg,
    required Color badgeColor,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.transparent,
            width: 2,
          ),
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
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : iconBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    size: 22,
                    color: isSelected ? Colors.white : iconColor,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    badgeText,
                    style: AppTypography.labelSm.copyWith(
                      color: badgeColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 9.5,
                    ),
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.labelLg.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTypography.labelSm.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showGuidelinesSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('DIU Campus Ride Sharing Rules', style: AppTypography.headlineSm),
            const SizedBox(height: 12),
            Text(
              '1. Only verified DIU student ID holders can offer or request seats.\n'
              '2. Fares are purely for peer fuel cost sharing (non-commercial).\n'
              '3. Bike drivers must provide a clean passenger helmet.\n'
              '4. Female-only rides are strictly reserved for female student peers.\n'
              '5. Dial Campus Security (Ext. 4410) in any emergency.',
              style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant, height: 1.6),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Understood'),
            ),
          ],
        ),
      ),
    );
  }
}
