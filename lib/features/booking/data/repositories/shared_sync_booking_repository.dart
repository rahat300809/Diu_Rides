import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'package:diu_ride/core/config/app_config.dart';
import 'package:diu_ride/core/storage/preferences_service.dart';
import 'package:diu_ride/features/booking/data/models/booking_model.dart';
import 'package:diu_ride/features/booking/data/repositories/booking_repository.dart';
import 'package:diu_ride/features/booking/data/repositories/mock_booking_repository.dart';
import 'package:diu_ride/features/rides/data/repositories/rides_repository.dart';

class SharedSyncBookingRepository implements BookingRepository {
  final RidesRepository ridesRepository;
  final PreferencesService preferences;
  late final MockBookingRepository _localFallback;
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 4),
    receiveTimeout: const Duration(seconds: 4),
  ));

  SharedSyncBookingRepository({
    required this.ridesRepository,
    required this.preferences,
  }) {
    _localFallback = MockBookingRepository(ridesRepository: ridesRepository);
  }

  String get _apiBase {
    if (kIsWeb) {
      final origin = Uri.base.origin;
      return '$origin/ride/api';
    }
    return AppConfig.current.apiBaseUrl;
  }

  @override
  Future<BookingModel> requestSeat({
    required String rideId,
    required String passengerId,
    required String passengerName,
    required String passengerDept,
    required String passengerPhone,
    required String pickupPoint,
    required String dropoffPoint,
    required int seatsBooked,
    required double totalFare,
  }) async {
    final booking = BookingModel(
      id: 'b_${const Uuid().v4().substring(0, 8)}',
      rideId: rideId,
      passengerId: passengerId,
      passengerName: passengerName,
      passengerDept: passengerDept,
      passengerPhone: passengerPhone,
      pickupPoint: pickupPoint,
      dropoffPoint: dropoffPoint,
      seatsBooked: seatsBooked,
      totalFare: totalFare,
      status: BookingStatus.requested,
      requestedAt: DateTime.now(),
    );

    // 1. Post to central server
    try {
      await _dio.post(
        '$_apiBase/bookings',
        data: booking.toJson(),
      );
      debugPrint('Booking sent to central backend: ${booking.id}');
    } catch (e) {
      debugPrint('Note: Central booking post error (using local): $e');
    }

    // 2. Deduct seats
    try {
      await ridesRepository.updateRideSeats(rideId, seatsBooked);
    } catch (_) {}

    // 3. Cache to preferences
    try {
      final current = await getMyBookings(passengerId);
      final updated = [booking, ...current.where((b) => b.id != booking.id)];
      await preferences.saveSharedBookings(jsonEncode(updated.map((b) => b.toJson()).toList()));
    } catch (_) {}

    return booking;
  }

  @override
  Future<List<BookingModel>> getMyBookings(String passengerId) async {
    try {
      final response = await _dio.get('$_apiBase/bookings?passenger_id=$passengerId');
      if (response.statusCode == 200 && response.data is List) {
        return (response.data as List)
            .map((item) => BookingModel.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
      }
    } catch (e) {
      debugPrint('Get bookings error (fallback to cache): $e');
    }

    // Fallback to cached preferences
    final cached = preferences.getSharedBookings();
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = jsonDecode(cached) as List<dynamic>;
        return decoded
            .map((item) => BookingModel.fromJson(Map<String, dynamic>.from(item as Map)))
            .where((b) => b.passengerId == passengerId)
            .toList();
      } catch (_) {}
    }

    return _localFallback.getMyBookings(passengerId);
  }

  @override
  Future<List<BookingModel>> getBookingsForRide(String rideId) async {
    try {
      final response = await _dio.get('$_apiBase/bookings?ride_id=$rideId');
      if (response.statusCode == 200 && response.data is List) {
        return (response.data as List)
            .map((item) => BookingModel.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
      }
    } catch (e) {
      debugPrint('Get ride bookings error (fallback to cache): $e');
    }

    // Fallback to cache
    final cached = preferences.getSharedBookings();
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = jsonDecode(cached) as List<dynamic>;
        return decoded
            .map((item) => BookingModel.fromJson(Map<String, dynamic>.from(item as Map)))
            .where((b) => b.rideId == rideId)
            .toList();
      } catch (_) {}
    }

    return _localFallback.getBookingsForRide(rideId);
  }

  @override
  Future<bool> acceptBooking(String bookingId) async {
    try {
      await _dio.patch('$_apiBase/bookings', data: {'id': bookingId, 'status': 'accepted'});
      return true;
    } catch (e) {
      debugPrint('Accept booking error: $e');
      return _localFallback.acceptBooking(bookingId);
    }
  }

  @override
  Future<bool> rejectBooking(String bookingId) async {
    try {
      await _dio.patch('$_apiBase/bookings', data: {'id': bookingId, 'status': 'rejected'});
      return true;
    } catch (e) {
      debugPrint('Reject booking error: $e');
      return _localFallback.rejectBooking(bookingId);
    }
  }

  @override
  Future<bool> cancelBooking(String bookingId) async {
    try {
      await _dio.patch('$_apiBase/bookings', data: {'id': bookingId, 'status': 'cancelled'});
      return true;
    } catch (e) {
      return _localFallback.cancelBooking(bookingId);
    }
  }
}
