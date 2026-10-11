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
              Row(
                children: [
                  Text(
                    'Campus Moto Share',
                    style: AppTypography.headlineSm.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.onSurface,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF007AFF), Color(0xFF0051B3)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF007AFF).withOpacity(0.35),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.two_wheeler, size: 12, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'Bikes Only',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () => _showGuidelinesSheet(context),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Text(
                    'Moto Safety',
                    style: AppTypography.labelSm.copyWith(
                      color: const Color(0xFF007AFF),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2x2 Apple iOS 3D Grid of Moto Categories
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.48,
            children: [
              // 1. Standard Moto Share
              _buildCategoryCard(
                title: 'Standard Moto',
                subtitle: '1 seat • Avg ৳35',
                badgeText: 'Fastest',
                badgeBg: const Color(0xFFE8F5E9),
                badgeColor: const Color(0xFF2E7D32),
                icon: Icons.two_wheeler,
                iconColor: const Color(0xFF00C853),
                iconBg: const Color(0xFFE8F5E9),
                isSelected: selectedType == VehicleType.bike && !femaleOnlySelected,
                onTap: () => onSelectCategory(VehicleType.bike, false),
              ),

              // 2. Helmet Provided Moto
              _buildCategoryCard(
                title: 'Helmet Ready',
                subtitle: 'DOT clean helmet',
                badgeText: '🪖 Safety',
                badgeBg: const Color(0xFFE3F2FD),
                badgeColor: const Color(0xFF1565C0),
                icon: Icons.sports_motorsports,
                iconColor: const Color(0xFF007AFF),
                iconBg: const Color(0xFFE3F2FD),
                isSelected: false,
                onTap: () => onSelectCategory(VehicleType.bike, false),
              ),

              // 3. Female Peer Moto
              _buildCategoryCard(
                title: 'Female Moto',
                subtitle: 'Peer-to-peer verified',
                badgeText: 'Women Safe',
                badgeBg: const Color(0xFFFCE4EC),
                badgeColor: const Color(0xFFC2185B),
                icon: Icons.female,
                iconColor: const Color(0xFFE91E63),
                iconBg: const Color(0xFFFCE4EC),
                isSelected: femaleOnlySelected,
                onTap: () => onSelectCategory(null, true),
              ),

              // 4. Express Metro Link
              _buildCategoryCard(
                title: 'Metro Express',
                subtitle: 'Diabari corridor link',
                badgeText: '⚡ Non-Stop',
                badgeBg: const Color(0xFFFFF3E0),
                badgeColor: const Color(0xFFE65100),
                icon: Icons.bolt,
                iconColor: const Color(0xFFFF9800),
                iconBg: const Color(0xFFFFF3E0),
                isSelected: false,
                onTap: () => onSelectCategory(VehicleType.bike, false),
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
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF007AFF) : Colors.black.withOpacity(0.06),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? const Color(0xFF007AFF).withOpacity(0.18)
                  : Colors.black.withOpacity(0.05),
              blurRadius: isSelected ? 14 : 10,
              offset: const Offset(0, 4),
            ),
            const BoxShadow(
              color: Colors.white,
              blurRadius: 2,
              offset: Offset(0, -1),
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
            Text('DIU Campus Moto Sharing Rules', style: AppTypography.headlineSm.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Text(
              '1. Moto peer rides are strictly for 1 verified DIU student passenger.\n'
              '2. All riders must provide a clean passenger safety helmet.\n'
              '3. Cost sharing is non-commercial (peer fuel split avg ৳30-৳50).\n'
              '4. Female peer rides connect female riders with female students.\n'
              '5. Dial Campus Security (Ext. 4410) in any emergency.',
              style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant, height: 1.6),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF007AFF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('Understood'),
            ),
          ],
        ),
      ),
    );
  }
}
