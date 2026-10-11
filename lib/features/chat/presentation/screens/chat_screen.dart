import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/core/utils/date_time_utils.dart';
import 'package:diu_ride/core/utils/gps_location_service.dart';
import 'package:diu_ride/features/chat/presentation/providers/chat_provider.dart';
import 'package:diu_ride/features/safety/presentation/widgets/campus_voice_call_dialog.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String rideId;
  final String driverName;
  final String? peerName;
  final String vehicleModel;
  final String? peerPhone;
  final String? peerRole;

  const ChatScreen({
    super.key,
    required this.rideId,
    this.driverName = 'Ride Companion',
    this.peerName,
    this.vehicleModel = 'Campus Ride',
    this.peerPhone,
    this.peerRole,
  });

  String get displayName => peerName ?? driverName;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _messageController.text;
    if (text.trim().isEmpty) return;
    ref.read(chatNotifierProvider(widget.rideId).notifier).sendMessage(text);
    _messageController.clear();
    _scrollToBottom();
  }

  Future<void> _shareLocation() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Acquiring device GPS coordinates...'),
        duration: Duration(seconds: 1),
      ),
    );
    final pos = await GpsLocationService.getCurrentLocation();
    final lat = pos?.latitude ?? 23.8765;
    final lng = pos?.longitude ?? 90.3204;
    if (!mounted) return;
    ref.read(chatNotifierProvider(widget.rideId).notifier).shareLocation(lat, lng);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatNotifierProvider(widget.rideId));
    final displayName = widget.displayName;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceContainerLowest,
        elevation: 0.5,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primaryContainer,
              child: Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : 'C',
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(displayName, style: AppTypography.bodyLgMedium),
                    const SizedBox(width: 4),
                    const Icon(Icons.verified, size: 14, color: AppColors.primary),
                  ],
                ),
                Text(
                  '${widget.peerRole ?? widget.vehicleModel} • Live Chat',
                  style: AppTypography.labelSm.copyWith(color: AppColors.primary, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call, color: AppColors.primary),
            tooltip: 'Campus Voice Call',
            onPressed: () {
              CampusVoiceCallDialog.show(
                context,
                peerName: displayName,
                peerPhone: widget.peerPhone ?? '01712345678',
                peerRole: widget.peerRole ?? 'Ride Companion',
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Connection & Safety Strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: AppColors.primaryFixed.withOpacity(0.3),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Realtime encrypted campus chat • Zero spam policy',
                    style: AppTypography.labelSm.copyWith(
                      color: AppColors.onPrimaryFixedVariant,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Messages list
          Expanded(
            child: chatState.isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: chatState.messages.length,
                    itemBuilder: (context, index) {
                      final msg = chatState.messages[index];
                      return Align(
                        alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.78,
                          ),
                          decoration: BoxDecoration(
                            color: msg.isMe ? AppColors.primary : AppColors.surfaceContainerLowest,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: Radius.circular(msg.isMe ? 16 : 4),
                              bottomRight: Radius.circular(msg.isMe ? 4 : 16),
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: AppColors.cardShadow,
                                blurRadius: 4,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment:
                                msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              if (msg.isLocationShare || msg.text.contains('google.com/maps')) ...[
                                Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: msg.isMe ? Colors.white.withOpacity(0.18) : AppColors.surfaceContainerHigh,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.location_on,
                                            size: 16,
                                            color: msg.isMe ? AppColors.primaryFixed : AppColors.primary,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Live GPS Location',
                                            style: AppTypography.labelSm.copyWith(
                                              color: msg.isMe ? AppColors.primaryFixed : AppColors.primary,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (msg.sharedLat != null && msg.sharedLng != null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          'Lat: ${msg.sharedLat!.toStringAsFixed(4)}, Lng: ${msg.sharedLng!.toStringAsFixed(4)}',
                                          style: AppTypography.labelSm.copyWith(
                                            color: msg.isMe ? Colors.white70 : AppColors.outline,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 6),
                                      InkWell(
                                        onTap: () {
                                          final lat = msg.sharedLat ?? 23.8765;
                                          final lng = msg.sharedLng ?? 90.3204;
                                          final url = GpsLocationService.getGoogleMapsLocationUrl(lat, lng);
                                          GpsLocationService.openGoogleMaps(url);
                                        },
                                        borderRadius: BorderRadius.circular(6),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: msg.isMe ? Colors.white : AppColors.primary,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.map,
                                                size: 14,
                                                color: msg.isMe ? AppColors.primary : Colors.white,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Open in Google Maps',
                                                style: TextStyle(
                                                  color: msg.isMe ? AppColors.primary : Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (!msg.isMe && msg.senderName.isNotEmpty) ...[
                                Text(
                                  msg.senderName,
                                  style: AppTypography.labelSm.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                              ],
                              Text(
                                msg.text,
                                style: AppTypography.bodyMd.copyWith(
                                  color: msg.isMe ? AppColors.onPrimary : AppColors.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    DateTimeUtils.formatTime(msg.timestamp),
                                    style: AppTypography.labelSm.copyWith(
                                      color: msg.isMe
                                          ? AppColors.onPrimary.withOpacity(0.7)
                                          : AppColors.outline,
                                      fontSize: 10,
                                    ),
                                  ),
                                  if (msg.isMe) ...[
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.done_all,
                                      size: 13,
                                      color: AppColors.primaryFixed,
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Message input bar
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.cardShadow,
                    blurRadius: 8,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.my_location, color: AppColors.secondary),
                    tooltip: 'Share Campus Location',
                    onPressed: _shareLocation,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: AppTypography.bodyMd.copyWith(color: AppColors.outline),
                        filled: true,
                        fillColor: AppColors.surfaceContainerLow,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: AppColors.primary,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: AppColors.onPrimary, size: 18),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
