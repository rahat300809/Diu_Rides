import 'package:diu_ride/features/rides/data/models/ride_model.dart';
import 'package:diu_ride/features/rides/data/models/vehicle_model.dart';

abstract class RidesRepository {
  Future<List<RideModel>> getDepartingSoonRides();

  Stream<List<RideModel>> watchDepartingSoonRides();

  Future<List<RideModel>> getAllAvailableRides();

  Future<List<RideModel>> searchRides({
    String? pickupQuery,
    String? dropoffQuery,
    String? generalQuery,
    DateTime? departureTime,
    int? seatsNeeded,
    VehicleType? vehicleType,
    bool femaleOnly = false,
    bool verifiedOnly = false,
    bool sortByLowestPrice = false,
  });

  Future<RideModel?> getRideById(String id);

  Future<RideModel> createRide({
    String? driverId,
    String? driverName,
    String? driverPhone,
    String? driverDepartment,
    required String originName,
    required double originLat,
    required double originLng,
    required String destinationName,
    required double destinationLat,
    required double destinationLng,
    String? waypointName,
    required DateTime departureTime,
    required VehicleModel vehicle,
    required int availableSeats,
    required double farePerSeat,
    required bool isFemaleOnly,
  });

  Future<List<RideModel>> getMyOfferedRides(String driverId);

  Future<bool> cancelOfferedRide(String rideId);

  Future<bool> deleteRide(String rideId);

  Future<bool> startRide(String rideId, {double? startLat, double? startLng});

  Future<bool> completeRide(String rideId, {double? endLat, double? endLng});

  Future<bool> shareLiveLocation({
    required String rideId,
    required String userId,
    required String userName,
    required String role,
    required double latitude,
    required double longitude,
  });

  Future<void> updateRideSeats(String rideId, int seatsToDeduct);
}
