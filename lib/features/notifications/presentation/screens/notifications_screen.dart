import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/core/utils/date_time_utils.dart';
import 'package:diu_ride/features/notifications/data/models/notification_model.dart';
import 'package:diu_ride/features/notifications/presentation/providers/notifications_provider.dart';
import 'package:diu_ride/features/booking/presentation/providers/booking_provider.dart';

import 'package:diu_ride/core/providers/app_mode_provider.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  AppMode? _selectedFilter;

  @override
  Widget build(BuildContext context) {
    final notifications = ref.watch(notificationsProvider);
    final appMode = ref.watch(appModeProvider);
    final effectiveMode = _selectedFilter ?? appMode;

    List<NotificationModel> filteredNotifications = notifications;
    if (effectiveMode == AppMode.rider) {
      filteredNotifications = notifications.where((n) {
        return n.requiresAction ||
            n.type == NotificationType.rideRequest ||
            n.type == NotificationType.ridePublished ||
            n.type == NotificationType.rideCancelled ||
            n.type == NotificationType.chatMessage ||
            n.type == NotificationType.safetyAlert;
      }).toList();
    } else if (effectiveMode == AppMode.passenger) {
      filteredNotifications = notifications.where((n) {
        return !n.requiresAction && (
            n.type == NotificationType.rideAccepted ||
            n.type == NotificationType.rideRejected ||
            n.type == NotificationType.driverArriving ||
            n.type == NotificationType.rideStarted ||
            n.type == NotificationType.rideCompleted ||
            n.type == NotificationType.chatMessage ||
            n.type == NotificationType.safetyAlert
        );
      }).toList();
    }

    final pendingRequests = effectiveMode == AppMode.passenger
        ? <NotificationModel>[]
        : filteredNotifications.where((n) => n.requiresAction && !n.isRead).toList();
    final otherNotifications =
        filteredNotifications.where((n) => !n.requiresAction).toList();

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Row(
          children: [
            Text(
              'Notifications',
              style: AppTypography.headlineSm.copyWith(fontWeight: FontWeight.w700),
            ),
            if (filteredNotifications.any((n) => !n.isRead)) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${filteredNotifications.where((n) => !n.isRead).length} new',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (filteredNotifications.any((n) => !n.isRead))
            TextButton(
              onPressed: () =>
                  ref.read(notificationsProvider.notifier).markAllAsRead(),
              child: Text(
                'Mark all read',
                style: AppTypography.labelMd.copyWith(color: AppColors.primary),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterChips(effectiveMode),
          Expanded(
            child: filteredNotifications.isEmpty
                ? _buildEmptyState(effectiveMode)
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    children: [
                      // ── ALARM SECTION: Pending Driver Requests ─────────────────
                      if (pendingRequests.isNotEmpty) ...[
                        _buildSectionHeader(
                          '🔔 Action Required (Rider)',
                          '${pendingRequests.length} ride request(s) need your response',
                          isAlert: true,
                        ),
                        const SizedBox(height: 8),
                        ...pendingRequests
                            .map((n) => _RideRequestAlarmCard(notification: n)),
                        const SizedBox(height: 20),
                      ],

                      // ── REGULAR NOTIFICATIONS ──────────────────────────────────
                      if (otherNotifications.isNotEmpty) ...[
                        if (pendingRequests.isNotEmpty)
                          _buildSectionHeader('Recent Updates', null),
                        const SizedBox(height: 8),
                        ...otherNotifications
                            .map((n) => _NotificationCard(notification: n)),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(AppMode effectiveMode) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          _buildFilterChip('All Alerts', AppMode.all, effectiveMode, Icons.tune),
          const SizedBox(width: 8),
          _buildFilterChip('Rider Alerts', AppMode.rider, effectiveMode, Icons.two_wheeler),
          const SizedBox(width: 8),
          _buildFilterChip('Passenger Alerts', AppMode.passenger, effectiveMode, Icons.hail_rounded),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, AppMode mode, AppMode effectiveMode, IconData icon) {
    final isSelected = effectiveMode == mode;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilter = mode;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF141416) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF141416) : const Color(0xFFE5E7EB),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? const Color(0xFFFFA000) : Colors.grey[700],
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected ? Colors.white : const Color(0xFF141416),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppMode effectiveMode) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              color: AppColors.surfaceContainerLow,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_none_outlined,
              size: 40,
              color: AppColors.outline,
            ),
          ),
          const SizedBox(height: 16),
          Text('All caught up!', style: AppTypography.headlineSm),
          const SizedBox(height: 4),
          Text(
            effectiveMode == AppMode.rider
                ? 'No rider alerts or pending requests at this moment.'
                : (effectiveMode == AppMode.passenger
                    ? 'No passenger trip updates or driver alerts right now.'
                    : 'Ride requests and campus updates\nwill appear here.'),
            style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, String? subtitle,
      {bool isAlert = false}) {
    return Row(
      children: [
        if (isAlert)
          Container(
            width: 4,
            height: 18,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: AppColors.error,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: AppTypography.bodyLgMedium.copyWith(
                fontWeight: FontWeight.w700,
                color: isAlert ? AppColors.error : AppColors.onSurface,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle,
                style: AppTypography.labelSm
                    .copyWith(color: AppColors.onSurfaceVariant),
              ),
          ],
        ),
      ],
    );
  }
}

// =============================================================================
// RIDE REQUEST ALARM CARD (Driver view — with Accept / Reject)
// =============================================================================

class _RideRequestAlarmCard extends ConsumerWidget {
  final NotificationModel notification;

  const _RideRequestAlarmCard({required this.notification});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingState = ref.watch(bookingNotifierProvider);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF8F0), Color(0xFFFFF3E0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFF9800).withOpacity(0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF9800).withOpacity(0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9800).withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person_add_alt_1,
                    color: Color(0xFFE65100),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notification.title,
                        style: AppTypography.bodyLgMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFBF360C),
                        ),
                      ),
                      Text(
                        DateTimeUtils.formatRelativeTime(notification.timestamp),
                        style: AppTypography.labelSm.copyWith(
                          color: const Color(0xFFE65100).withOpacity(0.7),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                // Pulsing alarm indicator
                _PulsingDot(),
              ],
            ),
            const SizedBox(height: 10),

            // Body
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                notification.body,
                style: AppTypography.bodyMd
                    .copyWith(color: AppColors.onSurface, height: 1.4),
              ),
            ),
            const SizedBox(height: 14),

            // Action buttons — Uber driver style
            Row(
              children: [
                // Reject
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: bookingState.isLoading
                        ? null
                        : () => _handleReject(context, ref),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Decline'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: BorderSide(color: AppColors.error.withOpacity(0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Accept
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: bookingState.isLoading
                        ? null
                        : () => _handleAccept(context, ref),
                    icon: bookingState.isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_circle_outline, size: 18),
                    label: Text(bookingState.isLoading ? 'Processing…' : 'Accept Rider'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAccept(BuildContext context, WidgetRef ref) async {
    if (notification.relatedBookingId == null) return;

    final success = await ref.read(bookingNotifierProvider.notifier).acceptBooking(
          bookingId: notification.relatedBookingId!,
          rideId: notification.relatedRideId ?? '',
          driverName: 'You (Driver)',
          pickupPoint: notification.body,
        );

    // Dismiss the alarm notification
    ref.read(notificationsProvider.notifier).dismiss(notification.id);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor:
              success ? AppColors.primary : AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          content: Text(
            success
                ? '✅ Rider accepted! They\'ve been notified.'
                : 'Failed to accept booking.',
          ),
        ),
      );
    }
  }

  Future<void> _handleReject(BuildContext context, WidgetRef ref) async {
    if (notification.relatedBookingId == null) return;

    await ref.read(bookingNotifierProvider.notifier).rejectBooking(
          bookingId: notification.relatedBookingId!,
          rideId: notification.relatedRideId ?? '',
          driverName: 'You (Driver)',
        );

    ref.read(notificationsProvider.notifier).dismiss(notification.id);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          content: Text('Rider request declined.'),
        ),
      );
    }
  }
}

// =============================================================================
// REGULAR NOTIFICATION CARD
// =============================================================================

class _NotificationCard extends ConsumerWidget {
  final NotificationModel notification;

  const _NotificationCard({required this.notification});

  IconData _getIcon(NotificationType type) {
    switch (type) {
      case NotificationType.rideAccepted:
        return Icons.check_circle_outline;
      case NotificationType.rideRejected:
      case NotificationType.rideCancelled:
        return Icons.cancel_outlined;
      case NotificationType.driverArriving:
        return Icons.near_me_outlined;
      case NotificationType.rideStarted:
        return Icons.two_wheeler_outlined;
      case NotificationType.rideCompleted:
        return Icons.flag_outlined;
      case NotificationType.chatMessage:
        return Icons.chat_bubble_outline;
      case NotificationType.safetyAlert:
        return Icons.shield_outlined;
      case NotificationType.rideRequest:
        return Icons.person_add_alt_1_outlined;
      case NotificationType.ridePublished:
        return Icons.campaign_outlined;
    }
  }

  Color _getColor(NotificationType type) {
    switch (type) {
      case NotificationType.rideAccepted:
      case NotificationType.rideCompleted:
        return AppColors.primary;
      case NotificationType.rideRejected:
      case NotificationType.rideCancelled:
        return AppColors.error;
      case NotificationType.driverArriving:
      case NotificationType.rideStarted:
        return AppColors.secondary;
      case NotificationType.chatMessage:
        return AppColors.secondary;
      case NotificationType.safetyAlert:
        return AppColors.tertiary;
      case NotificationType.rideRequest:
      case NotificationType.ridePublished:
        return const Color(0xFFE65100);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _getColor(notification.type);
    return InkWell(
      onTap: () =>
          ref.read(notificationsProvider.notifier).markAsRead(notification.id),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: notification.isRead
              ? AppColors.surfaceContainerLowest
              : AppColors.primaryFixed.withOpacity(0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: notification.isRead
                ? AppColors.surfaceContainer
                : AppColors.primary.withOpacity(0.25),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 21,
              backgroundColor: color.withOpacity(0.12),
              child: Icon(_getIcon(notification.type), color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: AppTypography.bodyLgMedium.copyWith(
                            fontWeight: notification.isRead
                                ? FontWeight.w500
                                : FontWeight.w700,
                          ),
                        ),
                      ),
                      if (!notification.isRead)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    notification.body,
                    style: AppTypography.bodyMd.copyWith(
                      color: AppColors.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    DateTimeUtils.formatRelativeTime(notification.timestamp),
                    style: AppTypography.labelSm.copyWith(
                      color: AppColors.outline,
                      fontSize: 10,
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

// =============================================================================
// PULSING DOT ANIMATION (alarm indicator)
// =============================================================================

class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => Opacity(
        opacity: _animation.value,
        child: Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            color: Color(0xFFE65100),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
