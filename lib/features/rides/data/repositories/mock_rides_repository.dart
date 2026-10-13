import 'dart:async';
import 'package:uuid/uuid.dart';
import 'package:diu_ride/core/utils/h3_utils.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';
import 'package:diu_ride/features/rides/data/models/vehicle_model.dart';
import 'package:diu_ride/features/rides/data/repositories/rides_repository.dart';

class MockRidesRepository implements RidesRepository {
  final List<RideModel> _rides = [];

  MockRidesRepository();


  @override
  Stream<List<RideModel>> watchDepartingSoonRides() {
    return Stream.value([]);
  }

  @override
  Future<List<RideModel>> getDepartingSoonRides() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _rides.where((r) => r.status == RideStatus.published && r.availableSeats > 0).take(4).toList();
  }

  @override
  Future<List<RideModel>> getAllAvailableRides() async {
    await Future.delayed(const Duration(milliseconds: 250));
    return _rides.where((r) => r.status != RideStatus.cancelled && r.status != RideStatus.completed).toList();
  }

  @override
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
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    List<RideModel> results = List.from(_rides);

    // Filter out cancelled rides from general searches
    results = results.where((r) => r.status != RideStatus.cancelled).toList();

    // 1. General free-form search across driver name, origin, destination, corridor, vehicle
    if (generalQuery != null && generalQuery.trim().isNotEmpty) {
      final g = generalQuery.trim().toLowerCase();
      final isAb4 = g.contains('ab4') || g.contains('ab 4') || g.contains('ab-4');
      results = results.where((r) {
        final ab4Match = isAb4 && (
          r.originName.toLowerCase().contains('academic building 4') ||
          (r.originSubtitle?.toLowerCase().contains('academic building 4') ?? false) ||
          r.destinationName.toLowerCase().contains('academic building 4') ||
          (r.destinationSubtitle?.toLowerCase().contains('academic building 4') ?? false)
        );
        return r.originName.toLowerCase().contains(g) ||
          (r.originSubtitle?.toLowerCase().contains(g) ?? false) ||
          r.destinationName.toLowerCase().contains(g) ||
          (r.destinationSubtitle?.toLowerCase().contains(g) ?? false) ||
          r.driverName.toLowerCase().contains(g) ||
          r.driverDept.toLowerCase().contains(g) ||
          r.routeCorridor.toLowerCase().contains(g) ||
          r.vehicle.modelName.toLowerCase().contains(g) ||
          ab4Match;
      }).toList();
    }

    if (pickupQuery != null && pickupQuery.trim().isNotEmpty) {
      final q = pickupQuery.trim().toLowerCase();
      results = results.where((r) => r.originName.toLowerCase().contains(q) || (r.originSubtitle?.toLowerCase().contains(q) ?? false)).toList();
    }

    if (dropoffQuery != null && dropoffQuery.trim().isNotEmpty) {
      final q = dropoffQuery.trim().toLowerCase();
      results = results.where((r) => r.destinationName.toLowerCase().contains(q) || (r.destinationSubtitle?.toLowerCase().contains(q) ?? false)).toList();
    }

    if (seatsNeeded != null && seatsNeeded > 1) {
      results = results.where((r) => r.availableSeats >= seatsNeeded).toList();
    }

    if (vehicleType != null) {
      results = results.where((r) => r.vehicle.type == vehicleType).toList();
    }

    if (femaleOnly) {
      results = results.where((r) => r.isFemaleOnly).toList();
    }

    if (sortByLowestPrice) {
      results.sort((a, b) => a.farePerSeat.compareTo(b.farePerSeat));
    }

    return results;
  }

  @override
  Future<RideModel?> getRideById(String id) async {
    await Future.delayed(const Duration(milliseconds: 200));
    try {
      return _rides.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
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
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));

    final dist = H3Utils.calculateDistanceKm(originLat, originLng, destinationLat, destinationLng);
    final duration = H3Utils.estimateDurationMinutes(dist);

    final newRide = RideModel(
      id: 'ride_${const Uuid().v4().substring(0, 8)}',
      driverId: driverId ?? 'usr_driver',
      driverName: driverName ?? 'DIU Student Driver',
      driverPhotoUrl: null,
      driverDept: driverDepartment ?? 'CSE Dept',
      driverRating: 4.90,
      driverRideCount: 1,
      originName: originName,
      originLat: originLat,
      originLng: originLng,
      destinationName: destinationName,
      destinationLat: destinationLat,
      destinationLng: destinationLng,
      waypointName: waypointName,
      departureTime: departureTime,
      farePerSeat: farePerSeat,
      totalSeats: availableSeats,
      availableSeats: availableSeats,
      isFemaleOnly: isFemaleOnly,
      status: RideStatus.published,
      vehicle: vehicle,
      h3OriginIndex: H3Utils.latLngToH3(originLat, originLng),
      h3DestinationIndex: H3Utils.latLngToH3(destinationLat, destinationLng),
      routeCorridor: 'Ashulia Highway Corridor Active',
      distanceKm: dist > 0 ? dist : 15.0,
      durationMinutes: duration,
    );

    _rides.insert(0, newRide);
    return newRide;
  }

  @override
  Future<List<RideModel>> getMyOfferedRides(String driverId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _rides.where((r) => r.driverId == driverId).toList();
  }

  @override
  Future<bool> cancelOfferedRide(String rideId) async {
    final idx = _rides.indexWhere((r) => r.id == rideId);
    if (idx != -1) {
      _rides[idx] = _rides[idx].copyWith(status: RideStatus.cancelled);
      return true;
    }
    return false;
  }

  @override
  Future<bool> deleteRide(String rideId) async {
    _rides.removeWhere((r) => r.id == rideId);
    return true;
  }

  @override
  Future<bool> startRide(String rideId, {double? startLat, double? startLng}) async {
    final idx = _rides.indexWhere((r) => r.id == rideId);
    if (idx != -1) {
      final sLat = startLat ?? _rides[idx].originLat;
      final sLng = startLng ?? _rides[idx].originLng;
      _rides[idx] = _rides[idx].copyWith(
        status: RideStatus.active,
        startLat: sLat,
        startLng: sLng,
        startTime: DateTime.now(),
        startMapsLink: 'https://www.google.com/maps/search/?api=1&query=$sLat,$sLng',
      );
      return true;
    }
    return false;
  }

  @override
  Future<bool> completeRide(String rideId, {double? endLat, double? endLng}) async {
    final idx = _rides.indexWhere((r) => r.id == rideId);
    if (idx != -1) {
      final eLat = endLat ?? _rides[idx].destinationLat;
      final eLng = endLng ?? _rides[idx].destinationLng;
      final sLat = _rides[idx].startLat ?? _rides[idx].originLat;
      final sLng = _rides[idx].startLng ?? _rides[idx].originLng;
      _rides[idx] = _rides[idx].copyWith(
        status: RideStatus.completed,
        endLat: eLat,
        endLng: eLng,
        endTime: DateTime.now(),
        endMapsLink: 'https://www.google.com/maps/search/?api=1&query=$eLat,$eLng',
        routeMapsLink: 'https://www.google.com/maps/dir/?api=1&origin=$sLat,$sLng&destination=$eLat,$eLng&travelmode=driving',
      );
      return true;
    }
    return false;
  }

  @override
  Future<bool> shareLiveLocation({
    required String rideId,
    required String userId,
    required String userName,
    required String role,
    required double latitude,
    required double longitude,
  }) async {
    return true;
  }

  @override
  Future<void> updateRideSeats(String rideId, int seatsToDeduct) async {
    final idx = _rides.indexWhere((r) => r.id == rideId);
    if (idx != -1) {
      final current = _rides[idx];
      _rides[idx] = current.copyWith(
        availableSeats: (current.availableSeats - seatsToDeduct).clamp(0, current.totalSeats),
      );
    }
  }

  final List<dynamic> _passengerRequests = [];

  @override
  Future<List<dynamic>> getPassengerRequests() async => _passengerRequests;

  @override
  Future<dynamic> createPassengerRequest({
    required String passengerId,
    required String passengerName,
    required String passengerPhone,
    required String pickup,
    required String dropoff,
    required String requestedTime,
    double proposedFare = 50.0,
    String notes = '',
  }) async {
    final req = {
      'id': 'preq_${DateTime.now().millisecondsSinceEpoch}',
      'passengerId': passengerId,
      'passengerName': passengerName,
      'passengerPhone': passengerPhone,
      'pickup': pickup,
      'dropoff': dropoff,
      'requestedTime': requestedTime,
      'proposedFare': proposedFare,
      'notes': notes,
      'status': 'open',
      'createdAt': DateTime.now().toIso8601String(),
    };
    _passengerRequests.add(req);
    return req;
  }

  @override
  Future<bool> acceptPassengerRequest({
    required String requestId,
    required String driverId,
    required String driverName,
    required String driverPhone,
    required String driverBike,
  }) async => true;

  @override
  Future<bool> deletePassengerRequest(String requestId) async {
    _passengerRequests.removeWhere((r) => r is Map && r['id'] == requestId);
    return true;
  }

  @override
  Future<List<Map<String, dynamic>>> getCompletedRides({String? userId}) async => [];

  @override
  Future<bool> triggerAlertRing({
    required String targetUserId,
    String? targetName,
    String? senderId,
    required String senderName,
    required String rideId,
    String? ringId,
    String? message,
  }) async => true;

  @override
  Future<bool> stopAlertRing({
    required String targetUserId,
    String? senderId,
    String? ringId,
  }) async => true;
}
