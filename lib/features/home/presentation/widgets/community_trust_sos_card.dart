import 'package:flutter/material.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/constants/app_constants.dart';
import 'package:diu_ride/core/theme/app_typography.dart';

class CommunityTrustSosCard extends StatelessWidget {
  final VoidCallback onTriggerSos;
  final VoidCallback onCallControl;

  const CommunityTrustSosCard({
    super.key,
    required this.onTriggerSos,
    required this.onCallControl,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.primaryContainer],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(
              color: AppColors.cardShadow,
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.verified_user,
                            color: AppColors.primaryFixed,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '100% DIU STUDENT VERIFIED',
                            style: AppTypography.labelMd.copyWith(
                              color: AppColors.primaryFixed,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Safe, affordable & eco-friendly rides between Ashulia DSC, Uttara & Mirpur. Zero commission peer carpool.',
                        style: AppTypography.bodyMd.copyWith(
                          color: Colors.white.withOpacity(0.95),
                          height: 1.35,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),

                // Instant Campus SOS Emergency Button
                GestureDetector(
                  onTap: onTriggerSos,
                  child: Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.error.withOpacity(0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.sos, color: Colors.white, size: 24),
                        Text(
                          'DIU SOS',
                          style: AppTypography.labelSm.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 9,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Live Campus Proctor Helpline Footer
            Container(
              padding: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Colors.white.withOpacity(0.18),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.support_agent,
                        size: 15,
                        color: AppColors.primaryFixed,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'DSC Security Control: ${AppConstants.proctorExtension}',
                        style: AppTypography.labelSm.copyWith(
                          color: AppColors.primaryFixed,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  InkWell(
                    onTap: onCallControl,
                    child: Text(
                      'Call Control Desk',
                      style: AppTypography.labelSm.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
