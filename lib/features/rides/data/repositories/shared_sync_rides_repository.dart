import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'package:diu_ride/core/config/app_config.dart';
import 'package:diu_ride/core/storage/preferences_service.dart';
import 'package:diu_ride/core/utils/h3_utils.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';
import 'package:diu_ride/features/rides/data/models/vehicle_model.dart';
import 'package:diu_ride/features/rides/data/repositories/rides_repository.dart';
import 'package:diu_ride/features/rides/data/repositories/mock_rides_repository.dart';

class SharedSyncRidesRepository implements RidesRepository {
  final PreferencesService preferences;
  final MockRidesRepository _localFallback = MockRidesRepository();
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 4),
    receiveTimeout: const Duration(seconds: 4),
  ));

  SharedSyncRidesRepository({required this.preferences});

  String get _apiBase {
    if (kIsWeb) {
      final origin = Uri.base.origin;
      return '$origin/ride/api';
    }
    return AppConfig.current.apiBaseUrl;
  }

  @override
  Stream<List<RideModel>> watchDepartingSoonRides() {
    return Stream.periodic(const Duration(seconds: 5))
        .asyncMap((_) => getDepartingSoonRides())
        .asBroadcastStream();
  }

  @override
  Future<List<RideModel>> getDepartingSoonRides() async {
    final all = await getAllAvailableRides();
    return all
        .where((r) => r.status == RideStatus.published && r.availableSeats > 0)
        .take(5)
        .toList();
  }

  @override
  Future<List<RideModel>> getAllAvailableRides() async {
    try {
      final response = await _dio.get('$_apiBase/rides');
      if (response.statusCode == 200 && response.data is List) {
        final list = (response.data as List)
            .map((item) => RideModel.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
        
        // Cache to preferences
        try {
          final encoded = jsonEncode((response.data as List));
          await preferences.saveSharedRides(encoded);
        } catch (_) {}

        return list;
      }
    } catch (e) {
      debugPrint('SharedSyncRidesRepository get rides note (using cache/local): $e');
    }

    // Try reading from PreferencesService cache
    final cached = preferences.getSharedRides();
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = jsonDecode(cached) as List<dynamic>;
        return decoded
            .map((item) => RideModel.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
      } catch (_) {}
    }

    return _localFallback.getAllAvailableRides();
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
    final all = await getAllAvailableRides();
    List<RideModel> results = List.from(all);

    results = results.where((r) => r.status != RideStatus.cancelled).toList();

    if (generalQuery != null && generalQuery.trim().isNotEmpty) {
      final g = generalQuery.trim().toLowerCase();
      results = results.where((r) =>
          r.originName.toLowerCase().contains(g) ||
          (r.originSubtitle?.toLowerCase().contains(g) ?? false) ||
          r.destinationName.toLowerCase().contains(g) ||
          (r.destinationSubtitle?.toLowerCase().contains(g) ?? false) ||
          r.driverName.toLowerCase().contains(g) ||
          r.driverDept.toLowerCase().contains(g) ||
          r.routeCorridor.toLowerCase().contains(g) ||
          r.vehicle.modelName.toLowerCase().contains(g)).toList();
    }

    if (pickupQuery != null && pickupQuery.trim().isNotEmpty) {
      final q = pickupQuery.trim().toLowerCase();
      results = results.where((r) =>
          r.originName.toLowerCase().contains(q) ||
          (r.originSubtitle?.toLowerCase().contains(q) ?? false)).toList();
    }

    if (dropoffQuery != null && dropoffQuery.trim().isNotEmpty) {
      final q = dropoffQuery.trim().toLowerCase();
      results = results.where((r) =>
          r.destinationName.toLowerCase().contains(q) ||
          (r.destinationSubtitle?.toLowerCase().contains(q) ?? false)).toList();
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
    final all = await getAllAvailableRides();
    try {
      return all.firstWhere((r) => r.id == id);
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
    final dist = H3Utils.calculateDistanceKm(originLat, originLng, destinationLat, destinationLng);
    final duration = H3Utils.estimateDurationMinutes(dist);

    final newRide = RideModel(
      id: 'ride_${const Uuid().v4().substring(0, 8)}',
      driverId: driverId ?? 'usr_driver_${DateTime.now().millisecondsSinceEpoch}',
      driverName: driverName ?? 'DIU Student Driver',
      driverPhotoUrl: null,
      driverDept: driverDepartment ?? 'CSE',
      driverRating: 4.95,
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
      routeCorridor: 'Birulia - Ashulia Corridor',
      distanceKm: dist > 0 ? dist : 14.0,
      durationMinutes: duration,
    );

    // 1. Post to backend server
    try {
      await _dio.post(
        '$_apiBase/rides',
        data: newRide.toJson(),
      );
      debugPrint('Ride published to central backend: ${newRide.id}');
    } catch (e) {
      debugPrint('Note: Central backend post error: $e');
    }

    // 2. Cache in local preferences
    try {
      final currentList = await getAllAvailableRides();
      final updatedList = [newRide, ...currentList.where((r) => r.id != newRide.id)];
      final encoded = jsonEncode(updatedList.map((r) => r.toJson()).toList());
      await preferences.saveSharedRides(encoded);
    } catch (_) {}

    return newRide;
  }

  @override
  Future<List<RideModel>> getMyOfferedRides(String driverId) async {
    final all = await getAllAvailableRides();
    return all.where((r) => r.driverId == driverId).toList();
  }

  @override
  Future<bool> cancelOfferedRide(String rideId) async {
    try {
      await _dio.patch('$_apiBase/rides', data: {'id': rideId, 'status': 'cancelled'});
    } catch (_) {}
    return true;
  }

  @override
  Future<bool> deleteRide(String rideId) async {
    try {
      await _dio.delete('$_apiBase/rides?id=$rideId');
      debugPrint('Ride deleted from central backend: $rideId');
    } catch (e) {
      debugPrint('Note: Delete ride error: $e');
    }

    // Update preferences cache
    try {
      final currentList = await getAllAvailableRides();
      final updated = currentList.where((r) => r.id != rideId).toList();
      await preferences.saveSharedRides(jsonEncode(updated.map((r) => r.toJson()).toList()));
    } catch (_) {}

    return true;
  }

  @override
  Future<bool> startRide(String rideId, {double? startLat, double? startLng}) async {
    try {
      await _dio.post('$_apiBase/rides/$rideId/start', data: {
        'latitude': startLat,
        'longitude': startLng,
      });
    } catch (_) {
      try {
        await _dio.patch('$_apiBase/rides', data: {'id': rideId, 'status': 'active'});
      } catch (_) {}
    }
    await _localFallback.startRide(rideId, startLat: startLat, startLng: startLng);
    return true;
  }

  @override
  Future<bool> completeRide(String rideId, {double? endLat, double? endLng}) async {
    try {
      await _dio.post('$_apiBase/rides/$rideId/complete', data: {
        'latitude': endLat,
        'longitude': endLng,
      });
    } catch (_) {
      try {
        await _dio.patch('$_apiBase/rides', data: {'id': rideId, 'status': 'completed'});
      } catch (_) {}
    }
    await _localFallback.completeRide(rideId, endLat: endLat, endLng: endLng);
    return true;
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
    try {
      await _dio.post('$_apiBase/location/share', data: {
        'rideId': rideId,
        'userId': userId,
        'userName': userName,
        'role': role,
        'latitude': latitude,
        'longitude': longitude,
      });
      return true;
    } catch (e) {
      debugPrint('shareLiveLocation error: $e');
      return false;
    }
  }

  @override
  Future<void> updateRideSeats(String rideId, int seatsToDeduct) async {
    try {
      final ride = await getRideById(rideId);
      if (ride != null) {
        final newSeats = (ride.availableSeats - seatsToDeduct).clamp(0, ride.totalSeats);
        await _dio.patch('$_apiBase/rides', data: {'id': rideId, 'availableSeats': newSeats});
      }
    } catch (_) {}
  }
}
