import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

class GpsLocationService {
  GpsLocationService._();

  // Default fallback (DIU Permanent Campus, Ashulia)
  static const double defaultCampusLat = 23.8765;
  static const double defaultCampusLng = 90.3204;

  /// Fetch current mobile latitude & longitude
  static Future<Position?> getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('[GPS] Location services are disabled. Prompting or using fallback.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('[GPS] Location permissions denied.');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('[GPS] Location permissions permanently denied.');
        return null;
      }

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
    } catch (e) {
      debugPrint('[GPS] Error fetching location: $e');
      return null;
    }
  }

  /// Generate a Google Maps link for a single coordinate
  static String getGoogleMapsLocationUrl(double lat, double lng) {
    return 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
  }

  /// Generate a Google Maps turn-by-turn route directions link
  static String getGoogleMapsRouteUrl({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) {
    return 'https://www.google.com/maps/dir/?api=1&origin=$originLat,$originLng&destination=$destLat,$destLng&travelmode=driving';
  }

  /// Open any Google Maps URL in native Maps app or browser
  static Future<bool> openGoogleMaps(String urlString) async {
    try {
      final uri = Uri.parse(urlString);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        return await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
      return launched;
    } catch (e) {
      debugPrint('[GPS] Could not open Google Maps link: $e');
      return false;
    }
  }
}
