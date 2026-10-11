import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/auth/presentation/screens/login_screen.dart';
import 'package:diu_ride/features/dashboard/presentation/screens/my_rides_dashboard_screen.dart';
import 'package:diu_ride/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:diu_ride/features/safety/presentation/screens/emergency_contacts_screen.dart';
import 'package:diu_ride/features/chat/presentation/screens/campus_messages_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authNotifierProvider).user;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Student Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          children: [
            // Profile Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [BoxShadow(color: AppColors.cardShadow, blurRadius: 8, offset: Offset(0, 2))],
              ),
              child: Column(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 42,
                        backgroundColor: AppColors.primaryContainer,
                        child: Text(
                          (user?.name.isNotEmpty == true ? user!.name.substring(0, 1) : 'S'),
                          style: AppTypography.display.copyWith(color: Colors.white),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.verified, color: Colors.white, size: 16),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(user?.name ?? 'DIU Student', style: AppTypography.headlineSm),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primaryFixed.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      'DIU Verified Student • ${user?.department ?? 'CSE'}',
                      style: AppTypography.labelSm.copyWith(
                        color: AppColors.onPrimaryFixed,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Student ID: ${user?.studentId ?? 'N/A'}',
                    style: AppTypography.bodyMdMedium.copyWith(color: AppColors.onSurfaceVariant),
                  ),
                  Text(
                    user?.email ?? '',
                    style: AppTypography.labelSm.copyWith(color: AppColors.outline),
                  ),
                  const Divider(height: 28),

                  // Commute Stats Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatCol('Driver Rides', '${user?.totalRidesAsDriver ?? 0}'),
                      Container(width: 1, height: 32, color: AppColors.surfaceContainer),
                      _buildStatCol('Passenger Rides', '${user?.totalRidesAsPassenger ?? 0}'),
                      Container(width: 1, height: 32, color: AppColors.surfaceContainer),
                      _buildStatCol('Peer Rating', '${user?.rating ?? 4.90}★'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Vehicle Registration Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [BoxShadow(color: AppColors.cardShadow, blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.secondaryFixed,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.two_wheeler, color: AppColors.onSecondaryFixed, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Registered Motorcycle', style: AppTypography.bodyLgMedium),
                        Text(
                          user?.vehicleInfo ?? 'None (Offer a ride to register bike)',
                          style: AppTypography.labelSm.copyWith(color: AppColors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (user?.isDriverRegistered == true ? AppColors.primaryFixed : AppColors.surfaceContainer)
                          .withOpacity(0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      user?.isDriverRegistered == true ? 'Sticker Active' : 'Passenger',
                      style: AppTypography.labelSm.copyWith(
                        color: user?.isDriverRegistered == true ? AppColors.primary : AppColors.outline,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Navigation Options
            Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [BoxShadow(color: AppColors.cardShadow, blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: Column(
                children: [
                  _buildMenuTile(
                    icon: Icons.history,
                    title: 'My Campus Commutes',
                    subtitle: 'Driver and passenger ride history',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const MyRidesDashboardScreen()),
                      );
                    },
                  ),
                  const Divider(height: 1, indent: 56),
                  _buildMenuTile(
                    icon: Icons.chat_bubble_outline,
                    title: 'Campus Messages & Peer Calls',
                    subtitle: 'Real-time encrypted chats & voice calls with ride partners',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CampusMessagesScreen(
                            onExploreRides: () => Navigator.of(context).pop(),
                          ),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1, indent: 56),
                  _buildMenuTile(
                    icon: Icons.shield_outlined,
                    title: 'Campus Safety & Emergency Contacts',
                    subtitle: 'DIU Proctor hotline and guardian contacts',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const EmergencyContactsScreen()),
                      );
                    },
                  ),
                  const Divider(height: 1, indent: 56),
                  _buildMenuTile(
                    icon: Icons.notifications_none,
                    title: 'Notification Preferences',
                    subtitle: 'FCM push alerts for ride bookings and arrivals',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                      );
                    },
                  ),
                  const Divider(height: 1, indent: 56),
                  _buildMenuTile(
                    icon: Icons.lock_outline,
                    title: 'Campus Privacy & Community Terms',
                    subtitle: 'DIU peer code of conduct & zero commercial policy',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('DIU Code of Conduct: Strict peer-to-peer rules apply.')),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Logout Button
            OutlinedButton.icon(
              onPressed: () async {
                await ref.read(authNotifierProvider.notifier).logout();
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                }
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.logout),
              label: const Text('Sign Out of DIU Ride'),
            ),
            const SizedBox(height: 16),

            Text(
              'DIU Ride v1.0.0 (Production Build) • Daffodil Smart City, Ashulia',
              style: AppTypography.labelSm.copyWith(color: AppColors.outline, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCol(String label, String value) {
    return Column(
      children: [
        Text(value, style: AppTypography.headlineSm.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: AppTypography.labelSm.copyWith(color: AppColors.onSurfaceVariant, fontSize: 11)),
      ],
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.primary, size: 20),
      ),
      title: Text(title, style: AppTypography.bodyMdMedium),
      subtitle: Text(subtitle, style: AppTypography.labelSm.copyWith(fontSize: 11)),
      trailing: const Icon(Icons.chevron_right, color: AppColors.outline),
      onTap: onTap,
    );
  }
}
