import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:diu_ride/core/config/app_config.dart';
import 'package:diu_ride/core/storage/preferences_service.dart';
import 'package:diu_ride/core/storage/secure_storage_service.dart';
import 'package:diu_ride/features/auth/data/models/user_model.dart';
import 'package:diu_ride/features/auth/data/repositories/auth_repository.dart';
import 'package:diu_ride/features/auth/data/repositories/mock_auth_repository.dart';

class SharedSyncAuthRepository implements AuthRepository {
  final SecureStorageService secureStorage;
  final PreferencesService preferences;
  late final MockAuthRepository _fallback;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 4),
    receiveTimeout: const Duration(seconds: 4),
  ));

  UserModel? _currentUser;

  SharedSyncAuthRepository({
    required this.secureStorage,
    required this.preferences,
  }) {
    _fallback = MockAuthRepository(
      secureStorage: secureStorage,
      preferences: preferences,
    );
  }

  String get _apiBase {
    if (kIsWeb) {
      final origin = Uri.base.origin;
      return '$origin/ride/api';
    }
    return AppConfig.current.apiBaseUrl;
  }

  @override
  Future<UserModel> loginWithStudentId({
    required String name,
    required String studentId,
    required String email,
    required String phone,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanId = studentId.trim();
    final cleanName = name.trim().isNotEmpty ? name.trim() : 'DIU Student';

    try {
      final res = await _dio.post('$_apiBase/auth/login-student-id', data: {
        'name': cleanName,
        'studentId': cleanId,
        'email': cleanEmail,
        'phone': phone.trim(),
      });
      if (res.statusCode == 200 && res.data != null) {
        final user = UserModel.fromJson(Map<String, dynamic>.from(res.data['user'] as Map));
        await _persistUser(user);
        return user;
      }
    } catch (e) {
      debugPrint('SharedSyncAuth loginWithStudentId note: $e');
    }

    final user = await _fallback.loginWithStudentId(
      name: cleanName,
      studentId: cleanId,
      email: cleanEmail,
      phone: phone,
    );
    await _persistUser(user);
    return user;
  }

  @override
  Future<void> sendOtp(String phone) async {
    try {
      await _dio.post('$_apiBase/auth/send-otp', data: {'phone': phone});
    } catch (_) {}
  }

  @override
  Future<String> sendEmailOtp(String email) async {
    try {
      final res = await _dio.post('$_apiBase/auth/send-email-otp', data: {'email': email.trim().toLowerCase()});
      if (res.statusCode == 200 && res.data != null && res.data['otp'] != null) {
        return res.data['otp'].toString();
      }
    } catch (_) {}
    return await _fallback.sendEmailOtp(email);
  }

  @override
  Future<UserModel> verifyOtp({
    required String phone,
    required String otp,
  }) async {
    return _fallback.verifyOtp(phone: phone, otp: otp);
  }

  @override
  Future<UserModel> verifyEmailOtp({
    required String email,
    required String otp,
    required String studentId,
    required String phone,
    String? name,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanId = studentId.trim();
    final studentName = (name != null && name.trim().isNotEmpty) ? name.trim() : 'DIU Student';

    try {
      final res = await _dio.post('$_apiBase/auth/verify-email', data: {
        'email': cleanEmail,
        'otp': otp,
        'studentId': cleanId,
        'phone': phone.trim(),
        'name': studentName,
      });
      if (res.statusCode == 200 && res.data != null && res.data['user'] != null) {
        final user = UserModel.fromJson(Map<String, dynamic>.from(res.data['user'] as Map));
        await _persistUser(user);
        return user;
      }
    } catch (e) {
      debugPrint('SharedSyncAuth verifyEmailOtp note: $e');
    }

    final user = await _fallback.verifyEmailOtp(
      email: cleanEmail,
      otp: otp,
      studentId: cleanId,
      phone: phone,
      name: studentName,
    );
    await _persistUser(user);
    return user;
  }

  @override
  Future<UserModel?> restoreSession() async {
    // Keep app logged in while user doesn't manually log out!
    final cached = preferences.getUserJson();
    if (cached != null) {
      try {
        final decoded = jsonDecode(cached) as Map<String, dynamic>;
        _currentUser = UserModel.fromJson(decoded);
        return _currentUser;
      } catch (e) {
        debugPrint('restoreSession error: $e');
      }
    }
    return null;
  }

  @override
  Future<void> logout() async {
    try {
      await _dio.post('$_apiBase/auth/logout');
    } catch (_) {}
    try {
      await secureStorage.clearTokens();
    } catch (_) {}
    try {
      await preferences.clearUser();
    } catch (_) {}
    _currentUser = null;
  }

  @override
  Future<UserModel> updateProfile(UserModel updatedUser) async {
    try {
      await _dio.post('$_apiBase/auth/profile', data: updatedUser.toJson());
    } catch (_) {}
    await _persistUser(updatedUser);
    return updatedUser;
  }

  @override
  Future<UserModel> loginWithIdAndPassword({
    required String identifier,
    required String password,
  }) async {
    final cleanId = identifier.trim();

    try {
      final res = await _dio.post('$_apiBase/auth/login', data: {
        'identifier': cleanId,
        'password': password,
      });
      if (res.statusCode == 200 && res.data != null && res.data['user'] != null) {
        final user = UserModel.fromJson(Map<String, dynamic>.from(res.data['user'] as Map));
        if (res.data['token'] != null) {
          await secureStorage.saveTokens(
            accessToken: res.data['token'].toString(),
            refreshToken: res.data['refreshToken']?.toString() ?? '',
          );
        }
        await _persistUser(user);
        await preferences.saveLastLoginIdentifier(cleanId);
        return user;
      }
    } catch (e) {
      debugPrint('Server login attempt note: $e, falling back to local credentials');
    }

    final user = await _fallback.loginWithIdAndPassword(
      identifier: identifier,
      password: password,
    );
    await _persistUser(user);
    await preferences.saveLastLoginIdentifier(cleanId);
    return user;
  }

  @override
  Future<String> registerWithDiuEmail({
    required String name,
    required String studentId,
    required String email,
    required String phone,
    required String password,
  }) async {
    try {
      final res = await _dio.post('$_apiBase/auth/register', data: {
        'name': name.trim(),
        'studentId': studentId.trim(),
        'email': email.trim().toLowerCase(),
        'phone': phone.trim(),
        'password': password,
      });
      if (res.statusCode == 200 && res.data != null && res.data['otp'] != null) {
        return res.data['otp'].toString();
      }
    } catch (e) {
      debugPrint('Server register note: $e');
    }

    return await _fallback.registerWithDiuEmail(
      name: name,
      studentId: studentId,
      email: email,
      phone: phone,
      password: password,
    );
  }

  @override
  Future<UserModel> verifyAndCompleteRegistration({
    required String otp,
  }) async {
    final pendingEmail = _fallback.pendingRegistrationEmail ?? '';
    try {
      final res = await _dio.post('$_apiBase/auth/verify-registration', data: {
        'email': pendingEmail,
        'otp': otp,
      });
      if (res.statusCode == 200 && res.data != null && res.data['user'] != null) {
        final user = UserModel.fromJson(Map<String, dynamic>.from(res.data['user'] as Map));
        await _persistUser(user);
        return user;
      }
    } catch (_) {}

    final user = await _fallback.verifyAndCompleteRegistration(otp: otp);
    await _persistUser(user);
    return user;
  }

  @override
  Future<String> requestPasswordReset({
    required String identifier,
  }) async {
    try {
      final res = await _dio.post('$_apiBase/auth/request-password-reset', data: {
        'identifier': identifier.trim(),
      });
      if (res.statusCode == 200 && res.data != null && res.data['otp'] != null) {
        return res.data['otp'].toString();
      }
    } catch (_) {}
    return await _fallback.requestPasswordReset(identifier: identifier);
  }

  @override
  Future<bool> verifyAndResetPassword({
    required String identifier,
    required String otp,
    required String newPassword,
  }) async {
    try {
      final res = await _dio.post('$_apiBase/auth/reset-password', data: {
        'identifier': identifier.trim(),
        'otp': otp,
        'newPassword': newPassword,
      });
      if (res.statusCode == 200) {
        return true;
      }
    } catch (_) {}
    return await _fallback.verifyAndResetPassword(
      identifier: identifier,
      otp: otp,
      newPassword: newPassword,
    );
  }

  @override
  Future<UserModel> updateDefaultAddress(String address) async {
    final user = _currentUser ?? (await restoreSession());
    if (user == null) {
      throw Exception('Not authenticated');
    }
    try {
      final res = await _dio.post('$_apiBase/auth/default-address', data: {
        'userId': user.id,
        'studentId': user.studentId,
        'email': user.email,
        'defaultAddress': address,
      });
      if (res.statusCode == 200 && res.data != null && res.data['user'] != null) {
        final updated = UserModel.fromJson(Map<String, dynamic>.from(res.data['user'] as Map));
        await _persistUser(updated);
        return updated;
      }
    } catch (e) {
      debugPrint('Server default address update note: $e');
    }

    final updated = user.copyWith(defaultAddress: address);
    await _persistUser(updated);
    return updated;
  }

  Future<void> _persistUser(UserModel user) async {
    _currentUser = user;
    final encoded = jsonEncode(user.toJson());
    await preferences.saveDedicatedAccount(user.studentId, encoded);
    await preferences.saveUserJson(encoded);
  }
}
