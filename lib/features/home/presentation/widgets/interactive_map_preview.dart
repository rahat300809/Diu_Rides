import 'package:flutter/material.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/theme/app_typography.dart';

class InteractiveMapPreview extends StatefulWidget {
  final Function(String driverName, String rideType) onSelectPin;
  final VoidCallback onRecenter;

  const InteractiveMapPreview({
    super.key,
    required this.onSelectPin,
    required this.onRecenter,
  });

  @override
  State<InteractiveMapPreview> createState() => _InteractiveMapPreviewState();
}

class _InteractiveMapPreviewState extends State<InteractiveMapPreview>
    with SingleTickerProviderStateMixin {
  late AnimationController _recenterController;

  @override
  void initState() {
    super.initState();
    _recenterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void dispose() {
    _recenterController.dispose();
    super.dispose();
  }

  void _handleRecenter() {
    _recenterController.forward(from: 0.0);
    widget.onRecenter();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 224,
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Color(0xFFE5EBE5),
            boxShadow: [
              BoxShadow(
                color: AppColors.cardShadow,
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Stylized Campus Map Surface Graphic
              CustomPaint(
                size: const Size(double.infinity, 224),
                painter: _CampusMapPainter(),
              ),

              // Gradient Scrim Overlays
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x55000000),
                      Colors.transparent,
                      Color(0x88000000),
                    ],
                    stops: [0.0, 0.45, 1.0],
                  ),
                ),
              ),

              // Top Demand Hexagon Alert Pill & Recenter Button
              Positioned(
                top: 10,
                left: 10,
                right: 10,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.92),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(color: Colors.black12, blurRadius: 4),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.local_fire_department,
                            color: AppColors.secondary,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'High Demand: Academic Bldg 4',
                            style: AppTypography.labelSm.copyWith(
                              color: AppColors.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    RotationTransition(
                      turns: _recenterController,
                      child: InkWell(
                        onTap: _handleRecenter,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.92),
                            shape: BoxShape.circle,
                            boxShadow: const [
                              BoxShadow(color: Colors.black12, blurRadius: 4),
                            ],
                          ),
                          child: const Icon(
                            Icons.my_location,
                            color: AppColors.onSurface,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Interactive Ride Pin 1: Sakib Hasan (Bike - Main Gate)
              Positioned(
                top: 52,
                left: 36,
                child: GestureDetector(
                  onTap: () => widget.onSelectPin('Sakib Hasan', 'Bike Share'),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 4),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '4m away',
                              style: AppTypography.labelSm.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2)),
                          ],
                        ),
                        child: const Icon(Icons.two_wheeler, color: Colors.white, size: 18),
                      ),
                    ],
                  ),
                ),
              ),

              // Interactive Ride Pin 2: Ayesha Siddiqa (Car - Knowledge City)
              Positioned(
                top: 76,
                right: 42,
                child: GestureDetector(
                  onTap: () => widget.onSelectPin('Ayesha Siddiqa', 'Student Carpool'),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 4),
                          ],
                        ),
                        child: Text(
                          '2 seats open',
                          style: AppTypography.labelSm.copyWith(
                            color: AppColors.secondary,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(
                          color: AppColors.secondary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2)),
                          ],
                        ),
                        child: const Icon(Icons.directions_car, color: Colors.white, size: 18),
                      ),
                    ],
                  ),
                ),
              ),

              // Ride Pin 3: Gate 2
              Positioned(
                bottom: 56,
                left: 110,
                child: GestureDetector(
                  onTap: () => widget.onSelectPin('Farhan Kabir', 'Bike Share'),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(
                      color: AppColors.primaryContainer,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Colors.black26, blurRadius: 4),
                      ],
                    ),
                    child: const Icon(Icons.two_wheeler, color: Colors.white, size: 16),
                  ),
                ),
              ),

              // Ride Pin 4: Micro Shuttle (Campus Bus Terminal)
              Positioned(
                bottom: 48,
                right: 90,
                child: GestureDetector(
                  onTap: () => widget.onSelectPin('Green Shuttle', 'Micro Shuttle'),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 4),
                          ],
                        ),
                        child: Text(
                          'HiAce • 6 min',
                          style: AppTypography.labelSm.copyWith(
                            color: AppColors.primaryContainer,
                            fontWeight: FontWeight.bold,
                            fontSize: 9,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(
                          color: AppColors.primaryContainer,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2)),
                          ],
                        ),
                        child: const Icon(Icons.airport_shuttle, color: Colors.white, size: 18),
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom Map Status Bar
              Positioned(
                bottom: 8,
                left: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.inverseSurface.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.near_me,
                            color: AppColors.primaryFixed,
                            size: 15,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '14 Active Student Rides in Ashulia Zone',
                            style: AppTypography.labelSm.copyWith(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Live',
                        style: AppTypography.labelSm.copyWith(
                          color: AppColors.primaryFixed,
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
      ),
    );
  }
}

/// Custom painter rendering a beautiful campus map vector layout with roads & lake
class _CampusMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFFE8EFE9);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Green Campus Parks
    final parkPaint = Paint()..color = const Color(0xFFD6E8D8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(15, 20, 110, 80), const Radius.circular(12)),
      parkPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(size.width - 130, 40, 110, 100), const Radius.circular(12)),
      parkPaint,
    );

    // Campus Lake (Blue)
    final lakePaint = Paint()..color = const Color(0xFFD0E3FF);
    final lakePath = Path()
      ..moveTo(size.width * 0.42, 60)
      ..quadraticBezierTo(size.width * 0.52, 90, size.width * 0.48, 140)
      ..quadraticBezierTo(size.width * 0.44, 180, size.width * 0.55, 210)
      ..lineTo(size.width * 0.62, 210)
      ..quadraticBezierTo(size.width * 0.52, 140, size.width * 0.58, 60)
      ..close();
    canvas.drawPath(lakePath, lakePaint);

    // Highway roads
    final roadPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 9
      ..style = PaintingStyle.stroke;

    final roadBorderPaint = Paint()
      ..color = const Color(0xFFCBD5CB)
      ..strokeWidth = 11
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(0, size.height * 0.5)
      ..quadraticBezierTo(size.width * 0.35, size.height * 0.45, size.width * 0.5, size.height * 0.3)
      ..quadraticBezierTo(size.width * 0.65, size.height * 0.15, size.width, size.height * 0.25);

    final branchPath = Path()
      ..moveTo(size.width * 0.5, size.height * 0.3)
      ..quadraticBezierTo(size.width * 0.55, size.height * 0.65, size.width * 0.85, size.height);

    canvas.drawPath(path, roadBorderPaint);
    canvas.drawPath(path, roadPaint);
    canvas.drawPath(branchPath, roadBorderPaint);
    canvas.drawPath(branchPath, roadPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
