import 'package:diu_ride/features/rides/data/models/vehicle_model.dart';

enum RideStatus { published, active, completed, cancelled }

class RideModel {
  final String id;
  final String driverId;
  final String driverName;
  final String? driverPhotoUrl;
  final String driverDept;
  final String? driverPhone;
  final double driverRating;
  final int driverRideCount;
  final String originName;
  final String? originSubtitle;
  final double originLat;
  final double originLng;
  final String destinationName;
  final String? destinationSubtitle;
  final double destinationLat;
  final double destinationLng;
  final String? waypointName;
  final DateTime departureTime;
  final double farePerSeat;
  final int totalSeats;
  final int availableSeats;
  final bool isFemaleOnly;
  final RideStatus status;
  final VehicleModel vehicle;
  final String? h3OriginIndex;
  final String? h3DestinationIndex;
  final String routeCorridor;
  final double distanceKm;
  final int durationMinutes;

  const RideModel({
    required this.id,
    required this.driverId,
    required this.driverName,
    this.driverPhotoUrl,
    required this.driverDept,
    this.driverPhone,
    this.driverRating = 5.0,
    this.driverRideCount = 0,
    required this.originName,
    this.originSubtitle,
    required this.originLat,
    required this.originLng,
    required this.destinationName,
    this.destinationSubtitle,
    required this.destinationLat,
    required this.destinationLng,
    this.waypointName,
    required this.departureTime,
    required this.farePerSeat,
    required this.totalSeats,
    required this.availableSeats,
    this.isFemaleOnly = false,
    this.status = RideStatus.published,
    required this.vehicle,
    this.h3OriginIndex,
    this.h3DestinationIndex,
    this.routeCorridor = 'Ashulia Highway Corridor',
    this.distanceKm = 14.0,
    this.durationMinutes = 30,
  });

  factory RideModel.fromJson(Map<String, dynamic> json) {
    return RideModel(
      id: json['id'] as String,
      driverId: json['driverId'] as String,
      driverName: json['driverName'] as String,
      driverPhotoUrl: json['driverPhotoUrl'] as String?,
      driverDept: json['driverDept'] as String? ?? 'DIU Student',
      driverPhone: json['driverPhone'] as String?,
      driverRating: (json['driverRating'] as num?)?.toDouble() ?? 5.0,
      driverRideCount: json['driverRideCount'] as int? ?? 0,
      originName: json['originName'] as String,
      originSubtitle: json['originSubtitle'] as String?,
      originLat: (json['originLat'] as num).toDouble(),
      originLng: (json['originLng'] as num).toDouble(),
      destinationName: json['destinationName'] as String,
      destinationSubtitle: json['destinationSubtitle'] as String?,
      destinationLat: (json['destinationLat'] as num).toDouble(),
      destinationLng: (json['destinationLng'] as num).toDouble(),
      waypointName: json['waypointName'] as String?,
      departureTime: DateTime.parse(json['departureTime'] as String),
      farePerSeat: (json['farePerSeat'] as num).toDouble(),
      totalSeats: json['totalSeats'] as int,
      availableSeats: json['availableSeats'] as int,
      isFemaleOnly: json['isFemaleOnly'] as bool? ?? false,
      status: RideStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => RideStatus.published,
      ),
      vehicle: VehicleModel.fromJson(json['vehicle'] as Map<String, dynamic>),
      h3OriginIndex: json['h3OriginIndex'] as String?,
      h3DestinationIndex: json['h3DestinationIndex'] as String?,
      routeCorridor: json['routeCorridor'] as String? ?? 'Ashulia Highway Corridor',
      distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 14.0,
      durationMinutes: json['durationMinutes'] as int? ?? 30,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'driverId': driverId,
      'driverName': driverName,
      'driverPhotoUrl': driverPhotoUrl,
      'driverDept': driverDept,
      'driverPhone': driverPhone,
      'driverRating': driverRating,
      'driverRideCount': driverRideCount,
      'originName': originName,
      'originSubtitle': originSubtitle,
      'originLat': originLat,
      'originLng': originLng,
      'destinationName': destinationName,
      'destinationSubtitle': destinationSubtitle,
      'destinationLat': destinationLat,
      'destinationLng': destinationLng,
      'waypointName': waypointName,
      'departureTime': departureTime.toIso8601String(),
      'farePerSeat': farePerSeat,
      'totalSeats': totalSeats,
      'availableSeats': availableSeats,
      'isFemaleOnly': isFemaleOnly,
      'status': status.name,
      'vehicle': vehicle.toJson(),
      'h3OriginIndex': h3OriginIndex,
      'h3DestinationIndex': h3DestinationIndex,
      'routeCorridor': routeCorridor,
      'distanceKm': distanceKm,
      'durationMinutes': durationMinutes,
    };
  }

  RideModel copyWith({
    int? availableSeats,
    RideStatus? status,
    String? driverPhone,
  }) {
    return RideModel(
      id: id,
      driverId: driverId,
      driverName: driverName,
      driverPhotoUrl: driverPhotoUrl,
      driverDept: driverDept,
      driverPhone: driverPhone ?? this.driverPhone,
      driverRating: driverRating,
      driverRideCount: driverRideCount,
      originName: originName,
      originSubtitle: originSubtitle,
      originLat: originLat,
      originLng: originLng,
      destinationName: destinationName,
      destinationSubtitle: destinationSubtitle,
      destinationLat: destinationLat,
      destinationLng: destinationLng,
      waypointName: waypointName,
      departureTime: departureTime,
      farePerSeat: farePerSeat,
      totalSeats: totalSeats,
      availableSeats: availableSeats ?? this.availableSeats,
      isFemaleOnly: isFemaleOnly,
      status: status ?? this.status,
      vehicle: vehicle,
      h3OriginIndex: h3OriginIndex,
      h3DestinationIndex: h3DestinationIndex,
      routeCorridor: routeCorridor,
      distanceKm: distanceKm,
      durationMinutes: durationMinutes,
    );
  }
}
