class PassengerRequestModel {
  final String id;
  final String passengerId;
  final String passengerName;
  final String passengerPhone;
  final String passengerDept;
  final String pickup;
  final String dropoff;
  final String requestedTime;
  final double proposedFare;
  final String notes;
  final String status;
  final String? acceptedByDriverId;
  final String? acceptedByDriverName;
  final String? acceptedByDriverPhone;
  final String? acceptedByDriverBike;
  final String createdAt;

  const PassengerRequestModel({
    required this.id,
    required this.passengerId,
    required this.passengerName,
    this.passengerPhone = '',
    this.passengerDept = 'CSE',
    required this.pickup,
    required this.dropoff,
    required this.requestedTime,
    this.proposedFare = 50.0,
    this.notes = '',
    this.status = 'open',
    this.acceptedByDriverId,
    this.acceptedByDriverName,
    this.acceptedByDriverPhone,
    this.acceptedByDriverBike,
    required this.createdAt,
  });

  bool get isOpen => status == 'open';
  bool get isAccepted => status == 'accepted';

  factory PassengerRequestModel.fromJson(Map<String, dynamic> json) {
    return PassengerRequestModel(
      id: json['id'] as String? ?? 'preq_${DateTime.now().millisecondsSinceEpoch}',
      passengerId: json['passengerId'] as String? ?? '',
      passengerName: json['passengerName'] as String? ?? 'DIU Student',
      passengerPhone: json['passengerPhone'] as String? ?? '',
      passengerDept: json['passengerDept'] as String? ?? 'CSE',
      pickup: json['pickup'] as String? ?? 'DIU Smart City',
      dropoff: json['dropoff'] as String? ?? 'Uttara',
      requestedTime: json['requestedTime'] as String? ?? 'Now',
      proposedFare: (json['proposedFare'] as num?)?.toDouble() ?? 50.0,
      notes: json['notes'] as String? ?? '',
      status: json['status'] as String? ?? 'open',
      acceptedByDriverId: json['acceptedByDriverId'] as String?,
      acceptedByDriverName: json['acceptedByDriverName'] as String?,
      acceptedByDriverPhone: json['acceptedByDriverPhone'] as String?,
      acceptedByDriverBike: json['acceptedByDriverBike'] as String?,
      createdAt: json['createdAt'] as String? ?? DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'passengerId': passengerId,
      'passengerName': passengerName,
      'passengerPhone': passengerPhone,
      'passengerDept': passengerDept,
      'pickup': pickup,
      'dropoff': dropoff,
      'requestedTime': requestedTime,
      'proposedFare': proposedFare,
      'notes': notes,
      'status': status,
      'acceptedByDriverId': acceptedByDriverId,
      'acceptedByDriverName': acceptedByDriverName,
      'acceptedByDriverPhone': acceptedByDriverPhone,
      'acceptedByDriverBike': acceptedByDriverBike,
      'createdAt': createdAt,
    };
  }
}
