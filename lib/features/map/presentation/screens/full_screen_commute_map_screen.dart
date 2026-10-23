import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:diu_ride/core/constants/campus_locations.dart';
import 'package:diu_ride/core/services/location_search_service.dart';
import 'package:diu_ride/core/utils/gps_location_service.dart';
import 'package:diu_ride/features/rides/data/models/ride_model.dart';
import 'package:diu_ride/features/rides/presentation/providers/rides_provider.dart';
import 'package:diu_ride/features/rides/presentation/screens/offer_ride_screen.dart';
import 'package:diu_ride/features/rides/presentation/screens/search_rides_screen.dart';
import 'package:diu_ride/features/rides/presentation/widgets/post_ride_request_sheet.dart';
import 'package:diu_ride/features/booking/presentation/widgets/booking_confirmation_sheet.dart';

class FullScreenCommuteMapScreen extends ConsumerStatefulWidget {
  final LatLng? initialDestination;
  final String? initialDestinationName;

  const FullScreenCommuteMapScreen({
    super.key,
    this.initialDestination,
    this.initialDestinationName,
  });

  @override
  ConsumerState<FullScreenCommuteMapScreen> createState() =>
      _FullScreenCommuteMapScreenState();
}

class _FullScreenCommuteMapScreenState
    extends ConsumerState<FullScreenCommuteMapScreen> {
  GoogleMapController? _mapController;
  final TextEditingController _searchController = TextEditingController();

  // Current GPS Location
  LatLng _currentLocation = const LatLng(
    CampusLocations.diuCenterLat,
    CampusLocations.diuCenterLng,
  );
  String _currentLocationName = 'DIU Smart City, Ashulia';
  bool _isLoadingGps = true;

  // Selected Destination
  LatLng? _selectedDestination;
  String _destinationName = '';
  double _routeDistanceKm = 0.0;
  int _routeEtaMinutes = 0;
  String? _nearestDroppingZone;
  int _walkMinutesToZone = 2;
  List<LatLng> _routePolylinePoints = [];
  String _routeSummary = '';
  bool _isCalculatingRoute = false;

  // Search Results & Suggestions
  List<LocationSearchResult> _searchResults = [];
  bool _isSearching = false;
  bool _showSearchResults = false;

  // Selected Ride Pin
  RideModel? _selectedRide;

  @override
  void initState() {
    super.initState();
    if (widget.initialDestination != null) {
      _selectedDestination = widget.initialDestination;
      _destinationName = widget.initialDestinationName ?? 'Destination';
      _searchController.text = _destinationName;
    }
    _initLiveLocation();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initLiveLocation() async {
    try {
      final pos = await GpsLocationService.getCurrentLocation();
      if (pos != null && mounted) {
        setState(() {
          _currentLocation = LatLng(pos.latitude, pos.longitude);
          _isLoadingGps = false;
          _currentLocationName = 'Your Live GPS Location';
        });

        if (_selectedDestination != null) {
          _calculateRouteStats(_selectedDestination!, _destinationName);
        } else {
          _animateCameraTo(_currentLocation, zoom: 15.0);
        }
      } else if (mounted) {
        setState(() => _isLoadingGps = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingGps = false);
    }
  }

  void _animateCameraTo(LatLng target, {double zoom = 15.0}) {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: zoom),
      ),
    );
  }

  void _fitRouteBounds() {
    if (_selectedDestination == null || _mapController == null) return;

    double southWestLat = math.min(_currentLocation.latitude, _selectedDestination!.latitude);
    double southWestLng = math.min(_currentLocation.longitude, _selectedDestination!.longitude);
    double northEastLat = math.max(_currentLocation.latitude, _selectedDestination!.latitude);
    double northEastLng = math.max(_currentLocation.longitude, _selectedDestination!.longitude);

    if (_routePolylinePoints.isNotEmpty) {
      for (final p in _routePolylinePoints) {
        if (p.latitude < 20.0 || p.latitude > 27.0 || p.longitude < 87.0 || p.longitude > 93.0) continue;
        if (p.latitude < southWestLat) southWestLat = p.latitude;
        if (p.longitude < southWestLng) southWestLng = p.longitude;
        if (p.latitude > northEastLat) northEastLat = p.latitude;
        if (p.longitude > northEastLng) northEastLng = p.longitude;
      }
    }

    // Ensure bounding box has non-zero padding so Google Map doesn't zoom out to entire planet
    if ((northEastLat - southWestLat).abs() < 0.008) {
      northEastLat += 0.004;
      southWestLat -= 0.004;
    }
    if ((northEastLng - southWestLng).abs() < 0.008) {
      northEastLng += 0.004;
      southWestLng -= 0.004;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(southWestLat, southWestLng),
      northeast: LatLng(northEastLat, northEastLng),
    );

    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 70));
  }

  Future<void> _calculateRouteStats(LatLng point, String name) async {
    setState(() {
      _selectedDestination = point;
      _destinationName = name;
      _isCalculatingRoute = true;
      _selectedRide = null;
    });

    final route = await LocationSearchService.getRoute(_currentLocation, point);

    // Identify nearest dropping zone
    String bestZone = 'DIU Main Gate 1';
    double minZoneDist = double.infinity;
    for (final z in LocationSearchService.campusLandmarks) {
      final d = Geolocator.distanceBetween(
        point.latitude,
        point.longitude,
        z.lat,
        z.lng,
      );
      if (d < minZoneDist) {
        minZoneDist = d;
        bestZone = z.title;
      }
    }
    final walkMins = math.max(1, (minZoneDist / 80.0).round());

    if (mounted && _selectedDestination == point) {
      setState(() {
        _routeDistanceKm = double.parse(route.distanceKm.toStringAsFixed(1));
        _routeEtaMinutes = route.durationMinutes;
        _routePolylinePoints = route.polylinePoints;
        _routeSummary = route.summary;
        _nearestDroppingZone = bestZone;
        _walkMinutesToZone = walkMins;
        _isCalculatingRoute = false;
      });
      _fitRouteBounds();
    }
  }

  void _onLocationSelected(LocationSearchResult result) async {
    _searchController.text = result.title;
    setState(() {
      _showSearchResults = false;
    });

    LatLng target = result.latLng;
    if (result.placeId != null) {
      final point = await LocationSearchService.getPlaceCoordinates(result.placeId!);
      if (point != null) target = point;
    }
    _calculateRouteStats(target, result.title);
  }

  void _onMapTapped(LatLng point) async {
    setState(() {
      _showSearchResults = false;
      _selectedRide = null;
    });
    final name = await LocationSearchService.reverseGeocode(point);
    _searchController.text = name;
    _calculateRouteStats(point, name);
  }

  void _handleSearchChanged(String text) async {
    if (text.trim().isEmpty) {
      setState(() {
        _searchResults = LocationSearchService.campusLandmarks.take(8).toList();
        _showSearchResults = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _showSearchResults = true;
    });

    final res = await LocationSearchService.search(text);
    if (mounted) {
      setState(() {
        _searchResults = res;
        _isSearching = false;
      });
    }
  }

  void _clearDestination() {
    setState(() {
      _selectedDestination = null;
      _destinationName = '';
      _routeDistanceKm = 0.0;
      _routeEtaMinutes = 0;
      _nearestDroppingZone = null;
      _selectedRide = null;
      _routePolylinePoints = [];
      _routeSummary = '';
      _searchController.clear();
      _showSearchResults = false;
    });
    _animateCameraTo(_currentLocation);
  }

  Set<Marker> _buildMarkers(List<RideModel> rides) {
    final markers = <Marker>{};

    // 1. Live User GPS Spot Marker
    markers.add(
      Marker(
        markerId: const MarkerId('live_user_spot'),
        position: _currentLocation,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
        infoWindow: InfoWindow(
          title: '📍 You Are Here',
          snippet: _currentLocationName,
        ),
      ),
    );

    // 2. Selected Destination Marker
    if (_selectedDestination != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('target_destination'),
          position: _selectedDestination!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: '🏁 $_destinationName',
            snippet: '$_routeDistanceKm km • ~$_routeEtaMinutes min commute',
          ),
        ),
      );
    }

    // 3. Official Dropping Zones Markers
    for (final zone in LocationSearchService.campusLandmarks.take(6)) {
      markers.add(
        Marker(
          markerId: MarkerId('drop_zone_${zone.title}'),
          position: zone.latLng,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(
            title: '⬡ Dropping Zone: ${zone.title}',
            snippet: zone.subtitle,
          ),
          onTap: () {
            _searchController.text = zone.title;
            _calculateRouteStats(zone.latLng, zone.title);
          },
        ),
      );
    }

    // 4. Live Active Motorbikes
    for (final ride in rides) {
      markers.add(
        Marker(
          markerId: MarkerId('biker_${ride.id}'),
          position: LatLng(ride.destinationLat, ride.destinationLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: InfoWindow(
            title: '🏍️ ${ride.driverName} (${ride.vehicle.modelName})',
            snippet: '➔ ${ride.destinationName} • ৳${ride.farePerSeat.toInt()} (Tap for info)',
          ),
          onTap: () {
            setState(() {
              _selectedRide = ride;
            });
          },
        ),
      );
    }

    return markers;
  }

  Set<Polyline> _buildPolylines() {
    final polylines = <Polyline>{};
    if (_selectedDestination != null && _routePolylinePoints.isNotEmpty) {
      // Google Maps double casing for clean road appearance
      polylines.add(
        Polyline(
          polylineId: const PolylineId('active_commute_casing'),
          points: _routePolylinePoints,
          color: const Color(0xFF1565C0),
          width: 7,
        ),
      );
      polylines.add(
        Polyline(
          polylineId: const PolylineId('active_commute_route'),
          points: _routePolylinePoints,
          color: const Color(0xFF42A5F5),
          width: 5,
        ),
      );
    } else if (_selectedDestination != null) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('active_commute_direct'),
          points: [_currentLocation, _selectedDestination!],
          color: const Color(0xFFE65100),
          width: 4,
          patterns: [PatternItem.dash(15), PatternItem.gap(8)],
        ),
      );
    }
    return polylines;
  }

  @override
  Widget build(BuildContext context) {
    final rides = ref.watch(allAvailableRidesProvider).value ?? [];

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // 1. Edge-to-Edge Full Screen Google Map
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _currentLocation,
              zoom: 14.5,
            ),
            markers: _buildMarkers(rides),
            polylines: _buildPolylines(),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: true,
            trafficEnabled: true,
            onMapCreated: (controller) {
              _mapController = controller;
              if (_selectedDestination != null) {
                _fitRouteBounds();
              }
            },
            onTap: _onMapTapped,
          ),

          // 2. Top Glassmorphic Google Search Bar & Back Button
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTopSearchBar(),
                    if (_showSearchResults) _buildSearchResultsOverlay(),
                  ],
                ),
              ),
            ),
          ),

          // 3. Floating Recenter / "My Spot" Button
          Positioned(
            right: 16,
            bottom: _selectedDestination != null || _selectedRide != null ? 220 : 100,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'recenter_gps_btn',
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0284C7),
                  elevation: 4,
                  onPressed: () {
                    _initLiveLocation();
                    _animateCameraTo(_currentLocation);
                  },
                  tooltip: 'Recenter My Spot',
                  child: _isLoadingGps
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0284C7)),
                        )
                      : const Icon(Icons.my_location),
                ),
                if (_selectedDestination != null) ...[
                  const SizedBox(height: 10),
                  FloatingActionButton.small(
                    heroTag: 'fit_route_btn',
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFFE65100),
                    elevation: 4,
                    onPressed: _fitRouteBounds,
                    tooltip: 'Fit Route',
                    child: const Icon(Icons.alt_route),
                  ),
                ],
              ],
            ),
          ),

          // 4. Bottom Interactive Action Sheet
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: _selectedRide != null
                  ? _buildSelectedRideBottomCard(_selectedRide!)
                  : _buildDestinationActionSheet(rides),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          // Back button
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A)),
            tooltip: 'Back',
            onPressed: () => Navigator.pop(context),
          ),

          // Text Field
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: _handleSearchChanged,
              onTap: () {
                if (_searchController.text.trim().isEmpty) {
                  setState(() {
                    _searchResults = LocationSearchService.campusLandmarks.take(8).toList();
                    _showSearchResults = true;
                  });
                }
              },
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
              ),
              decoration: InputDecoration(
                hintText: 'Search destination in Dhaka / Campus...',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w400,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),

          // Loading indicator or Clear button
          if (_isSearching)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE65100)),
              ),
            )
          else if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear, size: 18, color: Colors.grey),
              tooltip: 'Clear',
              onPressed: _clearDestination,
            )
          else
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.search, color: Color(0xFFE65100), size: 22),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchResultsOverlay() {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: _searchResults.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
        itemBuilder: (context, index) {
          final item = _searchResults[index];
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 15,
              backgroundColor: const Color(0xFFFFF7ED),
              child: Icon(
                item.category == 'campus'
                    ? Icons.school
                    : item.category == 'metro'
                        ? Icons.train
                        : Icons.location_on,
                size: 16,
                color: const Color(0xFFE65100),
              ),
            ),
            title: Text(
              item.title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              item.subtitle,
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _onLocationSelected(item),
          );
        },
      ),
    );
  }

  Widget _buildDestinationActionSheet(List<RideModel> allRides) {
    if (_selectedDestination == null) {
      return Container(
        margin: const EdgeInsets.all(14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.touch_app, color: Color(0xFFE65100), size: 18),
                SizedBox(width: 8),
                Text(
                  'Explore Campus & Dhaka Routes',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Tap any spot on the map or pick a major corridor below:',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: LocationSearchService.campusLandmarks.take(6).map((lm) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      backgroundColor: const Color(0xFFF8FAFC),
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                      label: Text(lm.title, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                      avatar: const Icon(Icons.place, size: 14, color: Color(0xFFE65100)),
                      onPressed: () => _onLocationSelected(lm),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      );
    }

    // Matching rides heading towards this corridor
    final matchingRides = allRides.where((r) {
      final dest = r.destinationName.toLowerCase();
      final sel = _destinationName.toLowerCase();
      return dest.contains(sel) || sel.contains(dest);
    }).toList();

    return Container(
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Destination Title and Distance/ETA badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _destinationName,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isCalculatingRoute
                          ? 'Calculating turn-by-turn road route...'
                          : '$_routeDistanceKm km road route • ~$_routeEtaMinutes min bike ride',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF0284C7), fontWeight: FontWeight.w700),
                    ),
                    if (_routeSummary.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '🛣️ Path: $_routeSummary',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                tooltip: 'Clear Route',
                onPressed: _clearDestination,
              ),
            ],
          ),

          // Dropping zone tag
          if (_nearestDroppingZone != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                children: [
                  const Text('⬡', style: TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.w900, fontSize: 13)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Nearest Dropping Zone: $_nearestDroppingZone (~$_walkMinutesToZone min walk)',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF1E40AF)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),

          // Action Buttons: Find Rides, Offer Ride, Request Ride
          Row(
            children: [
              // Find Rides Button
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    ref.read(rideSearchFilterProvider.notifier).setDropoff(_destinationName);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SearchRidesScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.search, size: 16),
                  label: Text(
                    matchingRides.isNotEmpty ? 'View Bikers (${matchingRides.length})' : 'Find Bikers',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE65100),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Offer Ride Button
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => OfferRideScreen(
                          onRidePublished: () {
                            Navigator.pop(context);
                          },
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.two_wheeler, size: 16),
                  label: const Text('Offer Ride', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFE65100),
                    side: const BorderSide(color: Color(0xFFE65100), width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Request Button
              InkWell(
                onTap: () {
                  PostRideRequestSheet.show(context);
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: const Icon(Icons.hail, color: Color(0xFF334155), size: 18),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedRideBottomCard(RideModel ride) {
    return Container(
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: const Color(0xFF86EFAC), width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.two_wheeler, color: Color(0xFF16A34A), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    ride.driverName,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '(${ride.vehicle.modelName})',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '৳${ride.farePerSeat.toInt()}',
                  style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF15803D)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${ride.originName} ➔ ${ride.destinationName}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: () {
                    BookingConfirmationSheet.show(
                      context: context,
                      ride: ride,
                      onBookingSuccess: () {
                        setState(() => _selectedRide = null);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('🎉 Seat Booking Request Sent!'),
                            backgroundColor: Color(0xFF16A34A),
                          ),
                        );
                      },
                    );
                  },
                  child: const Text('Book Seat Now', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey[700],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                ),
                onPressed: () => setState(() => _selectedRide = null),
                child: const Text('Close'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
