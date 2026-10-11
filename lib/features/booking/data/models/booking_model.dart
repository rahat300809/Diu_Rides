enum BookingStatus { requested, accepted, rejected, cancelled, completed }

class BookingModel {
  final String id;
  final String rideId;
  final String passengerId;
  final String passengerName;
  final String? passengerPhotoUrl;
  final String passengerDept;
  final String passengerPhone;
  final String pickupPoint;
  final String dropoffPoint;
  final int seatsBooked;
  final double totalFare;
  final BookingStatus status;
  final DateTime requestedAt;

  const BookingModel({
    required this.id,
    required this.rideId,
    required this.passengerId,
    required this.passengerName,
    this.passengerPhotoUrl,
    required this.passengerDept,
    required this.passengerPhone,
    required this.pickupPoint,
    required this.dropoffPoint,
    required this.seatsBooked,
    required this.totalFare,
    this.status = BookingStatus.requested,
    required this.requestedAt,
  });

  factory BookingModel.fromJson(Map<String, dynamic> json) {
    return BookingModel(
      id: json['id'] as String,
      rideId: json['rideId'] as String,
      passengerId: json['passengerId'] as String,
      passengerName: json['passengerName'] as String,
      passengerPhotoUrl: json['passengerPhotoUrl'] as String?,
      passengerDept: json['passengerDept'] as String? ?? 'DIU Student',
      passengerPhone: json['passengerPhone'] as String? ?? '',
      pickupPoint: json['pickupPoint'] as String,
      dropoffPoint: json['dropoffPoint'] as String,
      seatsBooked: json['seatsBooked'] as int,
      totalFare: (json['totalFare'] as num).toDouble(),
      status: BookingStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => BookingStatus.requested,
      ),
      requestedAt: DateTime.parse(json['requestedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'rideId': rideId,
      'passengerId': passengerId,
      'passengerName': passengerName,
      'passengerPhotoUrl': passengerPhotoUrl,
      'passengerDept': passengerDept,
      'passengerPhone': passengerPhone,
      'pickupPoint': pickupPoint,
      'dropoffPoint': dropoffPoint,
      'seatsBooked': seatsBooked,
      'totalFare': totalFare,
      'status': status.name,
      'requestedAt': requestedAt.toIso8601String(),
    };
  }

  BookingModel copyWith({BookingStatus? status}) {
    return BookingModel(
      id: id,
      rideId: rideId,
      passengerId: passengerId,
      passengerName: passengerName,
      passengerPhotoUrl: passengerPhotoUrl,
      passengerDept: passengerDept,
      passengerPhone: passengerPhone,
      pickupPoint: pickupPoint,
      dropoffPoint: dropoffPoint,
      seatsBooked: seatsBooked,
      totalFare: totalFare,
      status: status ?? this.status,
      requestedAt: requestedAt,
    );
  }
}
