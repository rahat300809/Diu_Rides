import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/features/chat/presentation/screens/campus_messages_screen.dart';
import 'package:diu_ride/features/home/presentation/screens/home_screen.dart';
import 'package:diu_ride/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:diu_ride/features/profile/presentation/screens/profile_screen.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';
import 'package:diu_ride/features/rides/presentation/screens/all_shared_rides_screen.dart';
import 'package:diu_ride/features/rides/presentation/screens/offer_ride_screen.dart';
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
  // 1 → All Shared Rides (Location filters, price sort, card details)
  // 2 → Offer Ride (Create bike ride)
  // 3 → Campus SMS & Community Messages
  // 4 → Profile

  final List<String> _titles = [
    'Home',
    'All Shared Rides',
    'Offer Ride',
    'Campus Messages',
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
    final noHeaderTabs = {0, 1, 3, 4}; // Home, All Rides, Messages, and Profile have their own headers

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: noHeaderTabs.contains(_currentTab)
          ? null
          : DiuAppHeader(
              title: _titles[_currentTab],
              onProfileTap: () => _onTabSelected(4),
              onNotificationsTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                );
              },
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

          // 1. All Shared Rides Screen
          const AllSharedRidesScreen(),

          // 2. Offer / Create Ride Screen
          OfferRideScreen(
            onRidePublished: () {
              _onTabSelected(1); // Jump to All Rides after publishing
            },
          ),

          // 3. Campus SMS & Direct Messages
          CampusMessagesScreen(
            onExploreRides: () => _onTabSelected(1),
          ),

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
