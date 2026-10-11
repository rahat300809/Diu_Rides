import 'package:flutter/material.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/theme/app_typography.dart';

class DestinationSearchCard extends StatelessWidget {
  final Function(String destination) onSelectDestination;
  final VoidCallback onTapSearch;

  const DestinationSearchCard({
    super.key,
    required this.onSelectDestination,
    required this.onTapSearch,
  });

  static const List<Map<String, dynamic>> _quickDestinations = [
    {
      'title': 'Uttara Sec 11',
      'full': 'Uttara Sector 11 (House Building)',
      'eta': '20m',
      'icon': Icons.location_on,
    },
    {
      'title': 'Mirpur 10',
      'full': 'Mirpur 10 Roundabout',
      'eta': '28m',
      'icon': Icons.directions_subway,
    },
    {
      'title': 'Dhanmondi 32',
      'full': 'Dhanmondi 32 (Metro Station)',
      'eta': '45m',
      'icon': Icons.school,
    },
    {
      'title': 'Birulia Bridge',
      'full': 'Birulia Bridge Stand',
      'eta': '10m',
      'icon': Icons.near_me,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Signature Uber-Style "Where to?" Search Container
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTapSearch,
              borderRadius: BorderRadius.circular(32),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEEEEE),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: Colors.black.withOpacity(0.06), width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Colors.black,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.search, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Where to?',
                        style: AppTypography.headlineSm.copyWith(
                          color: const Color(0xFF1B1B1B),
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    // "Now" Schedule Pill (Uber signature)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.access_time_filled, size: 15, color: Colors.black87),
                          const SizedBox(width: 5),
                          Text(
                            'Now',
                            style: AppTypography.labelMd.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(width: 3),
                          const Icon(Icons.keyboard_arrow_down, size: 16, color: Colors.black87),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Uber-Style Saved/Recent Destination Quick Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: _quickDestinations.map((dest) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: () => onSelectDestination(dest['full'] as String),
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFE2E2E2), width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.02),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            dest['icon'] as IconData,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            dest['title'] as String,
                            style: AppTypography.labelMd.copyWith(
                              color: const Color(0xFF222222),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F0F0),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              dest['eta'] as String,
                              style: AppTypography.labelSm.copyWith(
                                color: Colors.black54,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
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
        ],
      ),
    );
  }
}
