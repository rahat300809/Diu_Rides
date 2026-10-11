import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
// Chat accessible from Profile or via deep link
import 'package:diu_ride/features/home/presentation/screens/home_screen.dart';
import 'package:diu_ride/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:diu_ride/features/profile/presentation/screens/profile_screen.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';
import 'package:diu_ride/features/rides/presentation/screens/offer_ride_screen.dart';
import 'package:diu_ride/features/rides/presentation/screens/search_rides_screen.dart';
import 'package:diu_ride/shared/widgets/diu_app_header.dart';
import 'package:diu_ride/shared/widgets/diu_bottom_nav.dart';

class MainNavigationScreen extends ConsumerStatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  ConsumerState<MainNavigationScreen> createState() =>
      _MainNavigationScreenState();
}

class _MainNavigationScreenState extends ConsumerState<MainNavigationScreen> {
  int _currentTab = 0;

  // Tab index mapping:
  // 0 → Home
  // 1 → Find Ride (Search)
  // 2 → Offer Ride (Create)
  // 3 → Notifications / Alerts  ← NEW (was Chats)
  // 4 → Profile

  // Note: Chats is accessed from the profile or home, or can be moved back if needed.
  // The notifications tab replaces Chats in the primary nav since it's mission-critical.

  final List<String> _titles = [
    'Home',
    'Find Ride',
    'Offer Ride',
    'Notifications',
    'Profile',
  ];

  void _onTabSelected(int index) {
    setState(() {
      _currentTab = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Screens that render their own AppBar (no DiuAppHeader needed)
    final noHeaderTabs = {4}; // Profile has its own header

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: noHeaderTabs.contains(_currentTab)
          ? null
          : DiuAppHeader(
              title: _titles[_currentTab],
              onProfileTap: () => _onTabSelected(4),
              onNotificationsTap: () => _onTabSelected(3),
            ),
      body: IndexedStack(
        index: _currentTab,
        children: [
          // 0. Home Screen
          HomeScreen(
            onNavigateTab: _onTabSelected,
            onSearchQuery: (query) {
              ref.read(rideSearchFilterProvider.notifier).setDropoff(query);
            },
          ),

          // 1. Search / Find Ride Screen
          const SearchRidesScreen(),

          // 2. Offer / Create Ride Screen
          OfferRideScreen(
            onRidePublished: () {
              _onTabSelected(0); // Jump back to home after publishing
            },
          ),

          // 3. Notifications / Alerts Screen (was Chats — now mission-critical alerts)
          const NotificationsScreen(),

          // 4. Student Profile
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: DiuBottomNav(
        currentIndex: _currentTab,
        onTap: _onTabSelected,
        unreadChats: 0,
      ),
    );
  }
}
