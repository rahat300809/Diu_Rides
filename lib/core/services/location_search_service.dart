import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class LocationSearchResult {
  final String title;
  final String subtitle;
  final double lat;
  final double lng;
  final String category; // 'campus' | 'metro' | 'hub' | 'city'

  const LocationSearchResult({
    required this.title,
    required this.subtitle,
    required this.lat,
    required this.lng,
    this.category = 'city',
  });

  LatLng get latLng => LatLng(lat, lng);
}

class LocationSearchService {
  static const String googleApiKey = 'AIzaSyD-hl4Vshm6lqgUopu4rHbwmUbbPNA7kfA';

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 8),
      headers: {
        'User-Agent': 'DIU-Ride-App/1.0',
        'Accept': 'application/json',
      },
    ),
  );

  /// Official DIU Campus & Commute Landmarks for instant matching
  static const List<LocationSearchResult> campusLandmarks = [
    LocationSearchResult(
      title: 'DIU Main Gate 1',
      subtitle: 'Daffodil Smart City, Ashulia (Central Bike Stand)',
      lat: 23.8775,
      lng: 90.3201,
      category: 'campus',
    ),
    LocationSearchResult(
      title: 'DIU Gate 2 (Engineering Complex)',
      subtitle: 'DSC East Wing, Daffodil Smart City',
      lat: 23.8790,
      lng: 90.3215,
      category: 'campus',
    ),
    LocationSearchResult(
      title: 'Academic Building 4 (AB-4 Daffodil Tower)',
      subtitle: 'CSE, Software Engineering & Tech Depts, DSC',
      lat: 23.8781,
      lng: 90.3215,
      category: 'campus',
    ),
    LocationSearchResult(
      title: 'Campus Lake Bridge & Cafeteria',
      subtitle: 'Food Court & Lakeside connector, DSC',
      lat: 23.8755,
      lng: 90.3220,
      category: 'campus',
    ),
    LocationSearchResult(
      title: 'Transport Terminal & Bus Bay',
      subtitle: 'Behind Academic Bldg 1, DSC Ashulia',
      lat: 23.8762,
      lng: 90.3195,
      category: 'campus',
    ),
    LocationSearchResult(
      title: 'Birulia Bridge Crossing',
      subtitle: 'Birulia - Ashulia Highway Link',
      lat: 23.8685,
      lng: 90.3340,
      category: 'hub',
    ),
    LocationSearchResult(
      title: 'Uttara North Metro Station',
      subtitle: 'Diabari Exit 2, Metro Rail Line 6',
      lat: 23.8710,
      lng: 90.3800,
      category: 'metro',
    ),
    LocationSearchResult(
      title: 'Uttara House Building (Sector 7/9)',
      subtitle: 'Dhaka - Mymensingh Highway Overbridge',
      lat: 23.8735,
      lng: 90.3985,
      category: 'city',
    ),
    LocationSearchResult(
      title: 'Mirpur 10 Roundabout (Metro Hub)',
      subtitle: 'Metro Pillar 240, Mirpur Central, Dhaka',
      lat: 23.8069,
      lng: 90.3687,
      category: 'metro',
    ),
    LocationSearchResult(
      title: 'ECB Chattar (Matikata Road)',
      subtitle: 'Mirpur DOHS & Cantonment Flyover',
      lat: 23.8225,
      lng: 90.3934,
      category: 'hub',
    ),
    LocationSearchResult(
      title: 'Dhanmondi Campus (Sobhanbag)',
      subtitle: 'Mirpur Road, Dhanmondi 27, Dhaka',
      lat: 23.7538,
      lng: 90.3768,
      category: 'campus',
    ),
    LocationSearchResult(
      title: 'Savar Bazar Bus Stand',
      subtitle: 'Dhaka-Aricha Highway Overbridge',
      lat: 23.8488,
      lng: 90.2575,
      category: 'city',
    ),
    LocationSearchResult(
      title: 'Farmgate Overbridge & Metro',
      subtitle: 'Ananda Cinema & Indira Road Hub',
      lat: 23.7570,
      lng: 90.3888,
      category: 'metro',
    ),
    LocationSearchResult(
      title: 'Mohakhali Wireless Gate',
      subtitle: 'Mohakhali Interdistrict Bus Terminal',
      lat: 23.7780,
      lng: 90.4000,
      category: 'hub',
    ),
    LocationSearchResult(
      title: 'Kuril Flyover / Biswa Road',
      subtitle: 'Airport Road & 300 Feet Highway link',
      lat: 23.8180,
      lng: 90.4180,
      category: 'hub',
    ),
    LocationSearchResult(
      title: 'Hazrat Shahjalal International Airport',
      subtitle: 'Terminal 1 & 2, Airport Road',
      lat: 23.8510,
      lng: 90.4000,
      category: 'city',
    ),
  ];

  /// Live Search: Matches landmarks first, then calls Google Geocoding/Places API,
  /// with automated fallback to high-accuracy geocoding if Google Cloud restricts HTTP billing.
  static Future<List<LocationSearchResult>> search(String query) async {
    final clean = query.trim().toLowerCase();
    if (clean.isEmpty) {
      return campusLandmarks.take(8).toList();
    }

    final results = <LocationSearchResult>[];

    // 1. Instant Landmark Match
    for (final lm in campusLandmarks) {
      if (lm.title.toLowerCase().contains(clean) ||
          lm.subtitle.toLowerCase().contains(clean)) {
        results.add(lm);
      }
    }

    // 2. Try Google Geocoding API with project key
    try {
      final googleUrl =
          'https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent("$query, Dhaka, Bangladesh")}&key=$googleApiKey';
      final response = await _dio.get(googleUrl);
      if (response.statusCode == 200 && response.data is Map) {
        final status = response.data['status'] as String?;
        if (status == 'OK' && response.data['results'] is List) {
          final list = response.data['results'] as List;
          for (final item in list) {
            final formatted = item['formatted_address'] as String? ?? query;
            final loc = item['geometry']?['location'];
            if (loc != null) {
              final lat = (loc['lat'] as num).toDouble();
              final lng = (loc['lng'] as num).toDouble();
              results.add(
                LocationSearchResult(
                  title: formatted.split(',').first.trim(),
                  subtitle: formatted,
                  lat: lat,
                  lng: lng,
                  category: 'city',
                ),
              );
            }
          }
          if (results.isNotEmpty) return _deduplicate(results);
        }
      }
    } catch (_) {}

    // 3. Robust OpenStreetMap / Nominatim Fallback for Dhaka & Bangladesh
    try {
      final fallbackUrl =
          'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent("$query, Bangladesh")}&format=json&limit=6&addressdetails=1';
      final response = await _dio.get(fallbackUrl);
      if (response.statusCode == 200 && response.data is List) {
        final list = response.data as List;
        for (final item in list) {
          final displayName = item['display_name'] as String? ?? query;
          final lat = double.tryParse(item['lat']?.toString() ?? '') ?? 0.0;
          final lon = double.tryParse(item['lon']?.toString() ?? '') ?? 0.0;
          if (lat != 0.0 && lon != 0.0) {
            final parts = displayName.split(',');
            final title = parts.first.trim();
            final subtitle = parts.length > 1
                ? parts.skip(1).take(3).join(',').trim()
                : displayName;

            results.add(
              LocationSearchResult(
                title: title,
                subtitle: subtitle,
                lat: lat,
                lng: lon,
                category: 'city',
              ),
            );
          }
        }
      }
    } catch (_) {}

    return _deduplicate(results);
  }

  /// Reverse geocodes a map coordinate to a human readable location name
  static Future<String> reverseGeocode(LatLng point) async {
    // 1. Check if near any campus landmark (within 350 meters)
    for (final lm in campusLandmarks) {
      final dLat = (lm.lat - point.latitude).abs();
      final dLng = (lm.lng - point.longitude).abs();
      if (dLat < 0.003 && dLng < 0.003) {
        return lm.title;
      }
    }

    // 2. Try Google Geocoding reverse lookup
    try {
      final url =
          'https://maps.googleapis.com/maps/api/geocode/json?latlng=${point.latitude},${point.longitude}&key=$googleApiKey';
      final res = await _dio.get(url);
      if (res.statusCode == 200 && res.data['status'] == 'OK') {
        final results = res.data['results'] as List?;
        if (results != null && results.isNotEmpty) {
          final addr = results.first['formatted_address'] as String?;
          if (addr != null && addr.isNotEmpty) {
            return addr.split(',').take(2).join(', ').trim();
          }
        }
      }
    } catch (_) {}

    // 3. Fallback to OpenStreetMap reverse
    try {
      final url =
          'https://nominatim.openstreetmap.org/reverse?lat=${point.latitude}&lon=${point.longitude}&format=json';
      final res = await _dio.get(url);
      if (res.statusCode == 200 && res.data is Map) {
        final addr = res.data['display_name'] as String?;
        if (addr != null && addr.isNotEmpty) {
          return addr.split(',').take(2).join(', ').trim();
        }
      }
    } catch (_) {}

    return 'Selected Location (${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)})';
  }

  static List<LocationSearchResult> _deduplicate(List<LocationSearchResult> items) {
    final seen = <String>{};
    final unique = <LocationSearchResult>[];
    for (final item in items) {
      final key = '${item.lat.toStringAsFixed(3)}_${item.lng.toStringAsFixed(3)}';
      if (!seen.contains(key)) {
        seen.add(key);
        unique.add(item);
      }
    }
    return unique;
  }
}
