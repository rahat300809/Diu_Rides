class ChatMessage {
  final String id;
  final String rideId;
  final String senderId;
  final String senderName;
  final String text;
  final DateTime timestamp;
  final bool isMe;
  final bool isRead;
  final bool isLocationShare;
  final double? sharedLat;
  final double? sharedLng;
  final String? receiverId;

  const ChatMessage({
    required this.id,
    required this.rideId,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.timestamp,
    required this.isMe,
    this.isRead = true,
    this.isLocationShare = false,
    this.sharedLat,
    this.sharedLng,
    this.receiverId,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json, String currentUserId) {
    double? lat = (json['sharedLat'] as num?)?.toDouble();
    double? lng = (json['sharedLng'] as num?)?.toDouble();
    final text = (json['text'] as String?) ?? '';
    bool isLoc = json['isLocationShare'] as bool? ?? false;

    // Auto-detect & parse coordinates from Google Maps URL or text
    if ((lat == null || lng == null) && (isLoc || text.contains('google.com/maps') || text.contains('maps.google.com') || text.contains('📍'))) {
      final match = RegExp(r'query=(-?\d+\.\d+),(-?\d+\.\d+)').firstMatch(text) ??
          RegExp(r'(-?\d{1,2}\.\d{3,})\s*,\s*(-?\d{1,3}\.\d{3,})').firstMatch(text);
      if (match != null) {
        lat = double.tryParse(match.group(1)!);
        lng = double.tryParse(match.group(2)!);
        isLoc = true;
      }
    }

    return ChatMessage(
      id: json['id'] as String? ?? 'msg_${DateTime.now().millisecondsSinceEpoch}',
      rideId: json['rideId'] as String? ?? 'general',
      senderId: json['senderId'] as String? ?? '',
      senderName: json['senderName'] as String? ?? 'DIU Commuter',
      receiverId: json['receiverId'] as String?,
      text: text,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      isMe: json['senderId'] == currentUserId,
      isRead: json['isRead'] as bool? ?? true,
      isLocationShare: isLoc,
      sharedLat: lat,
      sharedLng: lng,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'rideId': rideId,
      'senderId': senderId,
      'senderName': senderName,
      'receiverId': receiverId,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
      'isRead': isRead,
      'isLocationShare': isLocationShare,
      'sharedLat': sharedLat,
      'sharedLng': sharedLng,
    };
  }
}
