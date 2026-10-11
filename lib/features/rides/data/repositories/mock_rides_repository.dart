import 'dart:async';
import 'package:uuid/uuid.dart';
import 'package:diu_ride/core/constants/campus_locations.dart';
import 'package:diu_ride/core/utils/h3_utils.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';
import 'package:diu_ride/features/rides/data/models/vehicle_model.dart';
import 'package:diu_ride/features/rides/data/repositories/rides_repository.dart';

class MockRidesRepository implements RidesRepository {
  final List<RideModel> _rides = [];

  MockRidesRepository() {
    _seedRides();
  }

  void _seedRides() {
    _rides.addAll([
      // Ride 1: Sakib Hasan (Bike) - Stitch Home Card 1
      RideModel(
        id: 'ride_sakib_01',
        driverId: 'usr_sakib_01',
        driverName: 'Sakib Hasan',
        driverPhotoUrl: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&w=300&q=80',
        driverDept: "CSE '22",
        driverRating: 4.9,
        driverRideCount: 142,
        originName: 'DIU Gate 1 (Main Entrance)',
        originSubtitle: 'Daffodil Smart City, Ashulia',
        originLat: CampusLocations.mainGate.latitude,
        originLng: CampusLocations.mainGate.longitude,
        destinationName: 'Uttara Diabari Metro Stn',
        destinationSubtitle: 'Exit Gate 2, Diabari',
        destinationLat: CampusLocations.uttaraMetro.latitude,
        destinationLng: CampusLocations.uttaraMetro.longitude,
        departureTime: DateTime.now().add(const Duration(minutes: 15)),
        farePerSeat: 40.0,
        totalSeats: 1,
        availableSeats: 1,
        isFemaleOnly: false,
        status: RideStatus.published,
        vehicle: const VehicleModel(
          id: 'v_sakib',
          type: VehicleType.bike,
          modelName: 'Yamaha FZ-X',
          color: 'Matte Blue',
          licensePlate: 'Dhaka Metro-HA 21-4321',
          hasPassengerHelmet: true,
        ),
        h3OriginIndex: CampusLocations.mainGate.h3Index,
        h3DestinationIndex: CampusLocations.uttaraMetro.h3Index,
        routeCorridor: 'Birulia - Uttara Express',
        distanceKm: 12.8,
        durationMinutes: 24,
      ),

      // Ride 2: Ayesha Siddiqa (Car) - Stitch Home Card 2
      RideModel(
        id: 'ride_ayesha_02',
        driverId: 'usr_ayesha_02',
        driverName: 'Ayesha Siddiqa',
        driverPhotoUrl: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=300&q=80',
        driverDept: "BBA '21",
        driverRating: 5.0,
        driverRideCount: 89,
        originName: 'Knowledge City (Main Roundabout)',
        originSubtitle: 'DSC Central Circle',
        originLat: CampusLocations.academicBldg4.latitude,
        originLng: CampusLocations.academicBldg4.longitude,
        destinationName: 'Mirpur 12 Bus Stand',
        destinationSubtitle: 'Near Metro Station Pillar 180',
        destinationLat: CampusLocations.mirpur10.latitude,
        destinationLng: CampusLocations.mirpur10.longitude,
        departureTime: DateTime.now().add(const Duration(minutes: 30)),
        farePerSeat: 80.0,
        totalSeats: 3,
        availableSeats: 2,
        isFemaleOnly: false,
        status: RideStatus.published,
        vehicle: const VehicleModel(
          id: 'v_ayesha',
          type: VehicleType.car,
          modelName: 'Toyota Axio (AC)',
          color: 'Pearl White',
          licensePlate: 'Dhaka Metro-GA 33-8822',
          hasAc: true,
          isSmokeFree: true,
          hasPhoneCharger: true,
          hasLuggageSpace: true,
        ),
        h3OriginIndex: CampusLocations.academicBldg4.h3Index,
        h3DestinationIndex: CampusLocations.mirpur10.h3Index,
        routeCorridor: 'Ashulia Highway Corridor',
        distanceKm: 15.2,
        durationMinutes: 32,
      ),

      // Ride 3: Rafiqul Islam (Top Recommended Bike) - Stitch Search Card 1
      RideModel(
        id: 'ride_rafiqul_03',
        driverId: 'usr_rafiqul_03',
        driverName: 'Rafiqul Islam',
        driverPhotoUrl: 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?auto=format&fit=crop&w=300&q=80',
        driverDept: 'SWE • 4th Year',
        driverRating: 4.9,
        driverRideCount: 118,
        originName: 'DIU Main Gate 1',
        originSubtitle: 'Daffodil Smart City',
        originLat: CampusLocations.mainGate.latitude,
        originLng: CampusLocations.mainGate.longitude,
        destinationName: 'House Building Metro',
        destinationSubtitle: 'Uttara Sector 11 (House Building)',
        destinationLat: CampusLocations.uttaraHouseBuilding.latitude,
        destinationLng: CampusLocations.uttaraHouseBuilding.longitude,
        departureTime: DateTime.now().add(const Duration(minutes: 20)),
        farePerSeat: 45.0,
        totalSeats: 1,
        availableSeats: 1,
        isFemaleOnly: false,
        status: RideStatus.published,
        vehicle: const VehicleModel(
          id: 'v_rafiqul',
          type: VehicleType.bike,
          modelName: 'Honda CB Shine (Red)',
          color: 'Red Metallic',
          licensePlate: 'Dhaka Metro-HA 55-9012',
          hasPassengerHelmet: true,
        ),
        h3OriginIndex: CampusLocations.mainGate.h3Index,
        h3DestinationIndex: CampusLocations.uttaraHouseBuilding.h3Index,
        routeCorridor: 'Express Highway',
        distanceKm: 14.0,
        durationMinutes: 30,
      ),

      // Ride 4: Farhana Akter (Women-to-Women Comfort Carpool) - Stitch Search Card 2
      RideModel(
        id: 'ride_farhana_04',
        driverId: 'usr_farhana_04',
        driverName: 'Farhana Akter',
        driverPhotoUrl: 'https://images.unsplash.com/photo-1544005313-94ddf0286df2?auto=format&fit=crop&w=300&q=80',
        driverDept: 'Pharmacy Dept',
        driverRating: 5.0,
        driverRideCount: 64,
        originName: 'DSC Sports Complex',
        originSubtitle: 'Cricket Ground North Pavilion',
        originLat: CampusLocations.sportsComplex.latitude,
        originLng: CampusLocations.sportsComplex.longitude,
        destinationName: 'Uttara Sector 11 (House Building)',
        destinationSubtitle: 'Dhaka - Mymensingh Highway',
        destinationLat: CampusLocations.uttaraHouseBuilding.latitude,
        destinationLng: CampusLocations.uttaraHouseBuilding.longitude,
        departureTime: DateTime.now().add(const Duration(minutes: 25)),
        farePerSeat: 80.0,
        totalSeats: 3,
        availableSeats: 2,
        isFemaleOnly: true,
        status: RideStatus.published,
        vehicle: const VehicleModel(
          id: 'v_farhana',
          type: VehicleType.car,
          modelName: 'Honda Grace Hybrid (White)',
          color: 'Taffeta White',
          licensePlate: 'Dhaka Metro-GA 19-3344',
          hasAc: true,
          isSmokeFree: true,
          hasLuggageSpace: true,
        ),
        h3OriginIndex: CampusLocations.sportsComplex.h3Index,
        h3DestinationIndex: CampusLocations.uttaraHouseBuilding.h3Index,
        routeCorridor: 'Birulia Bridge - Uttara Link',
        distanceKm: 16.0,
        durationMinutes: 35,
      ),

      // Ride 5: Tanvir Ahmed (Tracking Screen Active Ride)
      RideModel(
        id: 'ride_active_01',
        driverId: 'usr_diu_tanvir_201',
        driverName: 'Tanvir Ahmed',
        driverPhotoUrl: 'https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?auto=format&fit=crop&w=400&q=80',
        driverDept: 'CSE Dept • Batch 54 (ID: 201-15-****)',
        driverRating: 4.95,
        driverRideCount: 210,
        originName: 'Daffodil Knowledge City',
        originSubtitle: 'Main Gate Passenger Pickup Canopy (DSC)',
        originLat: CampusLocations.mainGate.latitude,
        originLng: CampusLocations.mainGate.longitude,
        destinationName: 'Uttara North Metro Station',
        destinationSubtitle: 'Exit Gate 2, Diabari (Direct Metro Link)',
        destinationLat: CampusLocations.uttaraMetro.latitude,
        destinationLng: CampusLocations.uttaraMetro.longitude,
        departureTime: DateTime.now().add(const Duration(minutes: 5)),
        farePerSeat: 80.0,
        totalSeats: 3,
        availableSeats: 2,
        isFemaleOnly: false,
        status: RideStatus.active,
        vehicle: const VehicleModel(
          id: 'v_tanvir',
          type: VehicleType.car,
          modelName: 'Toyota Corolla Axio',
          color: 'Silver Metallic',
          licensePlate: 'Dhaka Metro-GA 24-8891',
          hasAc: true,
          isSmokeFree: true,
          hasPhoneCharger: true,
          hasLuggageSpace: true,
        ),
        h3OriginIndex: CampusLocations.mainGate.h3Index,
        h3DestinationIndex: CampusLocations.uttaraMetro.h3Index,
        routeCorridor: 'Birulia - Ashulia Road',
        distanceKm: 16.4,
        durationMinutes: 35,
      ),
    ]);
  }

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
      results = results.where((r) =>
        r.originName.toLowerCase().contains(g) ||
        (r.originSubtitle?.toLowerCase().contains(g) ?? false) ||
        r.destinationName.toLowerCase().contains(g) ||
        (r.destinationSubtitle?.toLowerCase().contains(g) ?? false) ||
        r.driverName.toLowerCase().contains(g) ||
        r.driverDept.toLowerCase().contains(g) ||
        r.routeCorridor.toLowerCase().contains(g) ||
        r.vehicle.modelName.toLowerCase().contains(g)
      ).toList();
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
  Future<bool> startRide(String rideId) async {
    final idx = _rides.indexWhere((r) => r.id == rideId);
    if (idx != -1) {
      _rides[idx] = _rides[idx].copyWith(status: RideStatus.active);
      return true;
    }
    return false;
  }

  @override
  Future<bool> completeRide(String rideId) async {
    final idx = _rides.indexWhere((r) => r.id == rideId);
    if (idx != -1) {
      _rides[idx] = _rides[idx].copyWith(status: RideStatus.completed);
      return true;
    }
    return false;
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
}
