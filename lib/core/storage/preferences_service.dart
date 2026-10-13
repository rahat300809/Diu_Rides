import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:diu_ride/core/constants/app_constants.dart';

class PreferencesService {
  final SharedPreferences _prefs;

  PreferencesService(this._prefs);

  static Future<PreferencesService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return PreferencesService(prefs);
  }

  Future<void> saveUserJson(String jsonString) async {
    await _prefs.setString(AppConstants.userKey, jsonString);
  }

  String? getUserJson() {
    return _prefs.getString(AppConstants.userKey);
  }

  Future<void> clearUser() async {
    await _prefs.remove(AppConstants.userKey);
  }

  Future<void> saveDedicatedAccount(String studentId, String jsonString) async {
    await _prefs.setString('account_$studentId', jsonString);
    await _prefs.setString(AppConstants.userKey, jsonString);
  }

  String? getDedicatedAccount(String studentId) {
    return _prefs.getString('account_$studentId');
  }

  Future<void> savePendingRegistration(String jsonStr) async {
    await _prefs.setString('pending_registration_data', jsonStr);
  }

  String? getPendingRegistration() {
    return _prefs.getString('pending_registration_data');
  }

  Future<void> clearPendingRegistration() async {
    await _prefs.remove('pending_registration_data');
  }

  // --- Account & Credential Management for ID / Password & Email Verification ---

  Future<void> saveStudentAccount({
    required String studentId,
    required String email,
    required String password,
    required String userJson,
    required bool isVerified,
  }) async {
    final cleanId = studentId.trim();
    final cleanEmail = email.trim().toLowerCase();

    final accountMap = {
      'studentId': cleanId,
      'email': cleanEmail,
      'password': password,
      'userJson': userJson,
      'isVerified': isVerified,
      'updatedAt': DateTime.now().toIso8601String(),
    };

    await _prefs.setString('account_entry_$cleanId', jsonEncode(accountMap));
    await _prefs.setString('email_to_student_id_$cleanEmail', cleanId);
    await _prefs.setString('account_$cleanId', userJson);

    // Save as active user if verified
    if (isVerified) {
      await _prefs.setString(AppConstants.userKey, userJson);
    }
  }

  Map<String, dynamic>? getAccountCredentials(String identifier) {
    final clean = identifier.trim();
    String studentId = clean;

    // Check if identifier is an email
    if (clean.contains('@')) {
      final mappedId = _prefs.getString('email_to_student_id_${clean.toLowerCase()}');
      if (mappedId != null && mappedId.isNotEmpty) {
        studentId = mappedId;
      }
    }

    final rawJson = _prefs.getString('account_entry_$studentId');
    if (rawJson != null) {
      try {
        return jsonDecode(rawJson) as Map<String, dynamic>;
      } catch (_) {}
    }

    // Fallback: check basic account_$studentId
    final basicUserJson = _prefs.getString('account_$studentId');
    if (basicUserJson != null) {
      return {
        'studentId': studentId,
        'email': '$studentId@diu.edu.bd',
        'password': 'password123',
        'userJson': basicUserJson,
        'isVerified': true,
      };
    }

    return null;
  }

  Future<void> updateAccountPassword(String studentId, String newPassword) async {
    final creds = getAccountCredentials(studentId);
    if (creds != null) {
      creds['password'] = newPassword;
      creds['updatedAt'] = DateTime.now().toIso8601String();
      await _prefs.setString('account_entry_${creds['studentId']}', jsonEncode(creds));
    }
  }

  Future<void> setAccountVerified(String studentId, bool isVerified) async {
    final creds = getAccountCredentials(studentId);
    if (creds != null) {
      creds['isVerified'] = isVerified;
      creds['updatedAt'] = DateTime.now().toIso8601String();
      await _prefs.setString('account_entry_${creds['studentId']}', jsonEncode(creds));
      if (isVerified && creds['userJson'] != null) {
        await _prefs.setString(AppConstants.userKey, creds['userJson'] as String);
      }
    }
  }

  Future<void> saveLastLoginIdentifier(String identifier) async {
    await _prefs.setString('saved_login_identifier', identifier.trim());
  }

  String? getLastLoginIdentifier() {
    return _prefs.getString('saved_login_identifier');
  }

  Future<void> seedDefaultAccounts() async {
    // Production Mode: Do not seed mock demo accounts
  }

  Future<void> clearAllDemoRecords() async {
    final keys = _prefs.getKeys();
    for (final key in keys) {
      if (key.contains('201-15-14285') ||
          key.contains('demo') ||
          key.startsWith('shared_rides_') ||
          key.startsWith('chat_messages_') ||
          key.startsWith('cached_bookings_')) {
        await _prefs.remove(key);
      }
    }
  }

  bool isOnboardingComplete() {
    return _prefs.getBool(AppConstants.onboardingKey) ?? false;
  }

  Future<void> setOnboardingComplete(bool value) async {
    await _prefs.setBool(AppConstants.onboardingKey, value);
  }

  Future<void> saveSharedRides(String jsonString) async {
    await _prefs.setString('shared_campus_rides_v2', jsonString);
  }

  String? getSharedRides() {
    return _prefs.getString('shared_campus_rides_v2');
  }

  Future<void> saveSharedBookings(String jsonString) async {
    await _prefs.setString('shared_campus_bookings_v2', jsonString);
  }

  String? getSharedBookings() {
    return _prefs.getString('shared_campus_bookings_v2');
  }
}
