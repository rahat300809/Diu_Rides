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
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json, String currentUserId) {
    return ChatMessage(
      id: json['id'] as String,
      rideId: json['rideId'] as String,
      senderId: json['senderId'] as String,
      senderName: json['senderName'] as String,
      text: json['text'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      isMe: json['senderId'] == currentUserId,
      isRead: json['isRead'] as bool? ?? true,
      isLocationShare: json['isLocationShare'] as bool? ?? false,
      sharedLat: (json['sharedLat'] as num?)?.toDouble(),
      sharedLng: (json['sharedLng'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'rideId': rideId,
      'senderId': senderId,
      'senderName': senderName,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
      'isRead': isRead,
      'isLocationShare': isLocationShare,
      'sharedLat': sharedLat,
      'sharedLng': sharedLng,
    };
  }
}
