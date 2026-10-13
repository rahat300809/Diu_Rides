class CampusConversationModel {
  final String rideId;
  final String peerId;
  final String peerName;
  final String peerRole;
  final String peerPhone;
  final String peerDept;
  final String route;
  final String origin;
  final String destination;
  final String vehicleModel;
  final double fare;
  final String status;
  final String bookingId;
  final String lastMessage;
  final String lastTimestamp;
  final String lastSenderName;
  final int unreadCount;

  const CampusConversationModel({
    required this.rideId,
    required this.peerId,
    required this.peerName,
    required this.peerRole,
    required this.peerPhone,
    required this.peerDept,
    required this.route,
    required this.origin,
    required this.destination,
    required this.vehicleModel,
    required this.fare,
    required this.status,
    required this.bookingId,
    required this.lastMessage,
    required this.lastTimestamp,
    required this.lastSenderName,
    this.unreadCount = 0,
  });

  factory CampusConversationModel.fromJson(Map<String, dynamic> json) {
    return CampusConversationModel(
      rideId: json['rideId']?.toString() ?? '',
      peerId: json['peerId']?.toString() ?? '',
      peerName: json['peerName']?.toString() ?? 'DIU Student',
      peerRole: json['peerRole']?.toString() ?? 'Passenger',
      peerPhone: json['peerPhone']?.toString() ?? '',
      peerDept: json['peerDept']?.toString() ?? 'DIU Department',
      route: json['route']?.toString() ?? '',
      origin: json['origin']?.toString() ?? 'Campus Gate',
      destination: json['destination']?.toString() ?? 'Destination Spot',
      vehicleModel: json['vehicleModel']?.toString() ?? 'DIU Verified Bike',
      fare: (json['fare'] as num?)?.toDouble() ?? 35.0,
      status: json['status']?.toString() ?? 'active',
      bookingId: json['bookingId']?.toString() ?? '',
      lastMessage: json['lastMessage']?.toString() ?? 'Tap to open chat',
      lastTimestamp: json['lastTimestamp']?.toString() ?? '',
      lastSenderName: json['lastSenderName']?.toString() ?? '',
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
    );
  }
}
