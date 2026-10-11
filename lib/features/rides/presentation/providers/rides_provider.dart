import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';
import 'package:diu_ride/features/rides/data/models/vehicle_model.dart';
import 'package:diu_ride/features/rides/data/repositories/rides_repository.dart';
import 'package:diu_ride/features/rides/data/repositories/shared_sync_rides_repository.dart';

final ridesRepositoryProvider = Provider<RidesRepository>((ref) {
  final prefs = ref.watch(preferencesProvider);
  return SharedSyncRidesRepository(preferences: prefs);
});

final departingSoonRidesProvider = FutureProvider<List<RideModel>>((ref) async {
  final repo = ref.watch(ridesRepositoryProvider);
  return repo.getDepartingSoonRides();
});

final departingSoonRidesStreamProvider = StreamProvider<List<RideModel>>((ref) {
  final repo = ref.watch(ridesRepositoryProvider);
  return repo.watchDepartingSoonRides();
});

class RideSearchFilterState {
  final String pickupQuery;
  final String dropoffQuery;
  final String generalSearchQuery;
  final bool isAllRidesMode;
  final DateTime? departureTime;
  final int seatsNeeded;
  final VehicleType? vehicleType;
  final bool verifiedOnly;
  final bool femaleOnly;
  final bool sortByLowestPrice;
  final bool leavingSoon;

  const RideSearchFilterState({
    this.pickupQuery = '',
    this.dropoffQuery = '',
    this.generalSearchQuery = '',
    this.isAllRidesMode = true,
    this.departureTime,
    this.seatsNeeded = 1,
    this.vehicleType,
    this.verifiedOnly = false,
    this.femaleOnly = false,
    this.sortByLowestPrice = false,
    this.leavingSoon = false,
  });

  RideSearchFilterState copyWith({
    String? pickupQuery,
    String? dropoffQuery,
    String? generalSearchQuery,
    bool? isAllRidesMode,
    DateTime? departureTime,
    int? seatsNeeded,
    VehicleType? vehicleType,
    bool? verifiedOnly,
    bool? femaleOnly,
    bool? sortByLowestPrice,
    bool? leavingSoon,
    bool clearVehicleType = false,
  }) {
    return RideSearchFilterState(
      pickupQuery: pickupQuery ?? this.pickupQuery,
      dropoffQuery: dropoffQuery ?? this.dropoffQuery,
      generalSearchQuery: generalSearchQuery ?? this.generalSearchQuery,
      isAllRidesMode: isAllRidesMode ?? this.isAllRidesMode,
      departureTime: departureTime ?? this.departureTime,
      seatsNeeded: seatsNeeded ?? this.seatsNeeded,
      vehicleType: clearVehicleType ? null : (vehicleType ?? this.vehicleType),
      verifiedOnly: verifiedOnly ?? this.verifiedOnly,
      femaleOnly: femaleOnly ?? this.femaleOnly,
      sortByLowestPrice: sortByLowestPrice ?? this.sortByLowestPrice,
      leavingSoon: leavingSoon ?? this.leavingSoon,
    );
  }
}

class RideSearchNotifier extends StateNotifier<RideSearchFilterState> {
  RideSearchNotifier() : super(const RideSearchFilterState());

  void setGeneralSearch(String query) => state = state.copyWith(generalSearchQuery: query);
  void setPickup(String pickup) => state = state.copyWith(pickupQuery: pickup);
  void setDropoff(String dropoff) => state = state.copyWith(dropoffQuery: dropoff);
  void setAllRidesMode(bool isAll) => state = state.copyWith(isAllRidesMode: isAll);

  void swapLocations() {
    final oldPickup = state.pickupQuery;
    state = state.copyWith(
      pickupQuery: state.dropoffQuery,
      dropoffQuery: oldPickup,
    );
  }

  void setSeatsNeeded(int seats) => state = state.copyWith(seatsNeeded: seats);

  void toggleVehicleType(VehicleType type) {
    if (state.vehicleType == type) {
      state = state.copyWith(clearVehicleType: true);
    } else {
      state = state.copyWith(vehicleType: type);
    }
  }

  void toggleFemaleOnly() => state = state.copyWith(femaleOnly: !state.femaleOnly);
  void toggleVerifiedOnly() => state = state.copyWith(verifiedOnly: !state.verifiedOnly);
  void toggleLowestPrice() => state = state.copyWith(sortByLowestPrice: !state.sortByLowestPrice);

  void clearFilters() {
    state = const RideSearchFilterState(
      pickupQuery: '',
      dropoffQuery: '',
      generalSearchQuery: '',
      isAllRidesMode: true,
    );
  }
}

final rideSearchFilterProvider = StateNotifierProvider<RideSearchNotifier, RideSearchFilterState>((ref) {
  return RideSearchNotifier();
});

final allAvailableRidesProvider = FutureProvider<List<RideModel>>((ref) async {
  final repo = ref.watch(ridesRepositoryProvider);
  return repo.getAllAvailableRides();
});

final searchRidesResultsProvider = FutureProvider<List<RideModel>>((ref) async {
  final repo = ref.watch(ridesRepositoryProvider);
  final filter = ref.watch(rideSearchFilterProvider);

  return repo.searchRides(
    pickupQuery: filter.isAllRidesMode ? null : (filter.pickupQuery.isEmpty ? null : filter.pickupQuery),
    dropoffQuery: filter.isAllRidesMode ? null : (filter.dropoffQuery.isEmpty ? null : filter.dropoffQuery),
    generalQuery: filter.generalSearchQuery.isEmpty ? null : filter.generalSearchQuery,
    departureTime: filter.departureTime,
    seatsNeeded: filter.seatsNeeded,
    vehicleType: filter.vehicleType,
    femaleOnly: filter.femaleOnly,
    verifiedOnly: filter.verifiedOnly,
    sortByLowestPrice: filter.sortByLowestPrice,
  );
});
