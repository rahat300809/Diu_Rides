import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:diu_ride/core/constants/campus_locations.dart';
import 'package:diu_ride/core/utils/gps_location_service.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';

class LandingCommuteMapCard extends ConsumerStatefulWidget {
  final Function(String destination) onFindRides;
  final Function(String destination) onOfferRide;
  final Function(String destination) onRequestRide;
  final Function(RideModel ride)? onRideSelected;

  const LandingCommuteMapCard({
    super.key,
    required this.onFindRides,
    required this.onOfferRide,
    required this.onRequestRide,
    this.onRideSelected,
  });

  @override
  ConsumerState<LandingCommuteMapCard> createState() => _LandingCommuteMapCardState();
}

class _LandingCommuteMapCardState extends ConsumerState<LandingCommuteMapCard> {
  GoogleMapController? _mapController;

  // Default campus center: DIU Smart City, Ashulia
  LatLng _currentLocation = const LatLng(
    CampusLocations.diuCenterLat,
    CampusLocations.diuCenterLng,
  );
  bool _isLoadingGps = true;
  String _currentLocationName = 'DIU Smart City, Ashulia';
  bool _isMapInteractive = false;

  // Selected Destination
  LatLng? _selectedDestination;
  String _destinationName = '';
  double _routeDistanceKm = 0.0;
  int _routeEtaMinutes = 0;

  // Selected active ride pin
  RideModel? _tappedRide;

  // Quick preset locations
  final List<Map<String, dynamic>> _quickDestinations = [
    {
      'name': 'Uttara North Metro',
      'latLng': const LatLng(23.8710, 90.3800),
      'icon': Icons.train_outlined,
    },
    {
      'name': 'Mirpur 10 Circle',
      'latLng': const LatLng(23.8069, 90.3687),
      'icon': Icons.location_city,
    },
    {
      'name': 'Dhanmondi Sobhanbag',
      'latLng': const LatLng(23.7538, 90.3768),
      'icon': Icons.school_outlined,
    },
    {
      'name': 'Mohakhali Flyover',
      'latLng': const LatLng(23.7780, 90.4000),
      'icon': Icons.alt_route,
    },
    {
      'name': 'Savar Stand',
      'latLng': const LatLng(23.8475, 90.2570),
      'icon': Icons.directions_bus_outlined,
    },
    {
      'name': 'DIU Main Gate 1',
      'latLng': const LatLng(23.8775, 90.3201),
      'icon': Icons.shield_outlined,
    },
  ];

  @override
  void initState() {
    super.initState();
    _fetchLiveLocation();
  }

  Future<void> _fetchLiveLocation() async {
    try {
      final pos = await GpsLocationService.getCurrentLocation();
      if (pos != null && mounted) {
        setState(() {
          _currentLocation = LatLng(pos.latitude, pos.longitude);
          _isLoadingGps = false;
          _currentLocationName = 'Your Live GPS Location';
        });
        _animateCameraTo(_currentLocation);
      } else if (mounted) {
        setState(() {
          _isLoadingGps = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingGps = false);
    }
  }

  void _animateCameraTo(LatLng target, {double zoom = 14.5}) {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: zoom),
      ),
    );
  }

  void _fitRouteBounds() {
    if (_selectedDestination == null || _mapController == null) return;

    final southWestLat = math.min(_currentLocation.latitude, _selectedDestination!.latitude);
    final southWestLng = math.min(_currentLocation.longitude, _selectedDestination!.longitude);
    final northEastLat = math.max(_currentLocation.latitude, _selectedDestination!.latitude);
    final northEastLng = math.max(_currentLocation.longitude, _selectedDestination!.longitude);

    final bounds = LatLngBounds(
      southwest: LatLng(southWestLat, southWestLng),
      northeast: LatLng(northEastLat, northEastLng),
    );

    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
  }

  void _setDestination(LatLng point, String name) {
    final distMeters = Geolocator.distanceBetween(
      _currentLocation.latitude,
      _currentLocation.longitude,
      point.latitude,
      point.longitude,
    );
    final distKm = distMeters / 1000.0;
    // Estimated average bike speed in campus commute ~30 km/h + 5 min traffic buffer
    final etaMins = (distKm / 30.0 * 60).round() + 5;

    setState(() {
      _selectedDestination = point;
      _destinationName = name;
      _routeDistanceKm = double.parse(distKm.toStringAsFixed(1));
      _routeEtaMinutes = etaMins;
      _tappedRide = null;
    });

    _fitRouteBounds();
  }

  void _clearDestination() {
    setState(() {
      _selectedDestination = null;
      _destinationName = '';
      _routeDistanceKm = 0.0;
      _routeEtaMinutes = 0;
      _tappedRide = null;
    });
    _animateCameraTo(_currentLocation);
  }

  Set<Marker> _buildMarkers(List<RideModel> rides) {
    final markers = <Marker>{};

    // 1. Current Location Marker (Green / Cyan Pin)
    markers.add(
      Marker(
        markerId: const MarkerId('current_user_location'),
        position: _currentLocation,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
        infoWindow: InfoWindow(
          title: '📍 You Are Here',
          snippet: _currentLocationName,
        ),
      ),
    );

    // 2. Selected Destination Marker (Amber / Red Pin)
    if (_selectedDestination != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('selected_destination'),
          position: _selectedDestination!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: '🏁 Destination: $_destinationName',
            snippet: '$_routeDistanceKm km • ~$_routeEtaMinutes min commute',
          ),
        ),
      );
    }

    // 3. Active Peer Motorbike Pins on Map
    for (final ride in rides) {
      final rLat = ride.startLat ?? ride.originLat;
      final rLng = ride.startLng ?? ride.originLng;

      markers.add(
        Marker(
          markerId: MarkerId('ride_${ride.id}'),
          position: LatLng(rLat, rLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: InfoWindow(
            title: '🏍️ ${ride.driverName} (${ride.vehicle.modelName})',
            snippet: '➔ ${ride.destinationName} • ৳${ride.farePerSeat.toInt()}',
          ),
          onTap: () {
            setState(() {
              _tappedRide = ride;
            });
          },
        ),
      );
    }

    return markers;
  }

  Set<Polyline> _buildPolylines() {
    if (_selectedDestination == null) return {};

    return {
      Polyline(
        polylineId: const PolylineId('commute_route'),
        points: [_currentLocation, _selectedDestination!],
        color: const Color(0xFFE65100), // Radiant Sunset Amber
        width: 5,
        geodesic: true,
        patterns: [PatternItem.dash(20), PatternItem.gap(8)],
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final allRides = ref.watch(allAvailableRidesProvider).value ?? [];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: Live Interactive Map title and current GPS status
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE65100).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.map_rounded,
                        size: 18,
                        color: Color(0xFFE65100),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Live Campus & Commute Map',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          _isLoadingGps ? 'Locating GPS...' : 'Tap map to set where to go',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Recenter My Location Button
                InkWell(
                  onTap: () {
                    _fetchLiveLocation();
                    _animateCameraTo(_currentLocation);
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.my_location, size: 14, color: Color(0xFF0284C7)),
                        SizedBox(width: 4),
                        Text(
                          'My Spot',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0284C7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Google Map View Port (Rounded Container with ClipRRect)
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              height: 260,
              width: double.infinity,
              child: Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: _currentLocation,
                      zoom: 14.2,
                    ),
                    onMapCreated: (ctrl) {
                      _mapController = ctrl;
                      _animateCameraTo(_currentLocation);
                    },
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    compassEnabled: true,
                    scrollGesturesEnabled: _isMapInteractive,
                    zoomGesturesEnabled: _isMapInteractive,
                    rotateGesturesEnabled: _isMapInteractive,
                    tiltGesturesEnabled: _isMapInteractive,
                    gestureRecognizers: _isMapInteractive
                        ? {
                            Factory<OneSequenceGestureRecognizer>(
                              () => EagerGestureRecognizer(),
                            ),
                          }
                        : <Factory<OneSequenceGestureRecognizer>>{},
                    markers: _buildMarkers(allRides),
                    polylines: _buildPolylines(),
                    onTap: (point) {
                      _setDestination(
                        point,
                        'Dropped Pin (${point.latitude.toStringAsFixed(3)}, ${point.longitude.toStringAsFixed(3)})',
                      );
                    },
                  ),

                  // Top Right: Floating Pan / Scroll Mode Toggle Button
                  Positioned(
                    top: 10,
                    right: 12,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _isMapInteractive = !_isMapInteractive;
                          });
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: _isMapInteractive ? const Color(0xFFE65100) : Colors.white.withOpacity(0.95),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.12),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                            border: Border.all(
                              color: _isMapInteractive ? const Color(0xFFE65100) : const Color(0xFFE2E8F0),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isMapInteractive ? Icons.lock_open_rounded : Icons.pan_tool_outlined,
                                size: 13,
                                color: _isMapInteractive ? Colors.white : const Color(0xFF0F172A),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _isMapInteractive ? 'Pan Mode ON' : 'Touch to Pan',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: _isMapInteractive ? Colors.white : const Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Top subtle instruction pill (left aligned so it doesn't collide with toggle)
                  if (_selectedDestination == null)
                    Positioned(
                      top: 10,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.92),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.touch_app, size: 13, color: Color(0xFFE65100)),
                            SizedBox(width: 5),
                            Text(
                              'Tap map to drop destination',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Bottom Route Overlay Card (When destination is set)
                  if (_selectedDestination != null)
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.14),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                          border: Border.all(color: const Color(0xFFE65100).withOpacity(0.4)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Route Details Row
                            Row(
                              children: [
                                const Icon(Icons.location_on, color: Color(0xFFE65100), size: 18),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _destinationName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE65100).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '$_routeDistanceKm km • ~$_routeEtaMinutes min',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFE65100),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: _clearDestination,
                                  child: const Icon(Icons.close, size: 18, color: Colors.grey),
                                ),
                              ],
                            ),

                            const SizedBox(height: 10),

                            // Action buttons: Find Rides | Offer Ride | Request
                            Row(
                              children: [
                                // 1. Find Rides to Destination
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () => widget.onFindRides(_destinationName),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFE65100),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    icon: const Icon(Icons.search, size: 14),
                                    label: const Text(
                                      'Find Rides',
                                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),

                                // 2. Offer Ride Along This Route
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => widget.onOfferRide(_destinationName),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFFE65100),
                                      side: const BorderSide(color: Color(0xFFE65100)),
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    icon: const Icon(Icons.two_wheeler, size: 14),
                                    label: const Text(
                                      'Offer Ride',
                                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Bottom Active Ride Selected Overlay (When a bike marker is tapped)
                  if (_tappedRide != null && _selectedDestination == null)
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.14),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE65100).withOpacity(0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.two_wheeler, color: Color(0xFFE65100), size: 18),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _tappedRide!.driverName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  Text(
                                    '➔ ${_tappedRide!.destinationName} • ৳${_tappedRide!.farePerSeat.toInt()}',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                if (widget.onRideSelected != null) {
                                  widget.onRideSelected!(_tappedRide!);
                                } else {
                                  widget.onFindRides(_tappedRide!.destinationName);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE65100),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text('View Ride', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () => setState(() => _tappedRide = null),
                              child: const Icon(Icons.close, size: 18, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Quick Destination Pills Horizontal Selector
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Where do you want to go?',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    if (_selectedDestination != null)
                      GestureDetector(
                        onTap: _clearDestination,
                        child: const Text(
                          'Reset Pin',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFE65100),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: _quickDestinations.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final item = _quickDestinations[i];
                      final isSelected = _destinationName == item['name'];

                      return InkWell(
                        onTap: () {
                          _setDestination(item['latLng'] as LatLng, item['name'] as String);
                        },
                        borderRadius: BorderRadius.circular(18),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFFE65100)
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFFE65100)
                                  : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                item['icon'] as IconData,
                                size: 14,
                                color: isSelected ? Colors.white : const Color(0xFF64748B),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                item['name'] as String,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                  color: isSelected ? Colors.white : const Color(0xFF1E293B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
