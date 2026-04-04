// lib/screens/app/map/map_navigation_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class MapNavigationPage extends StatefulWidget {
  final double stationLat;
  final double stationLng;
  final String stationAddress;
  final String stationName;

  final double alertLat;
  final double alertLng;
  final String? alertAddress;

  final String apiKey;

  const MapNavigationPage({
    super.key,
    required this.stationLat,
    required this.stationLng,
    required this.stationAddress,
    required this.stationName,
    required this.alertLat,
    required this.alertLng,
    this.alertAddress,
    required this.apiKey,
  });

  @override
  State<MapNavigationPage> createState() => _MapNavigationPageState();
}

class _MapNavigationPageState extends State<MapNavigationPage>
    with TickerProviderStateMixin {
  GoogleMapController? _controller;

  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  List<LatLng> _polylineCoords = [];

  String _distance = "";
  String _duration = "";
  String _nextInstruction = "Continue straight";
  String _remainingDistance = "";
  String _remainingDuration = "";

  bool _isLoading = true;
  bool _isStartingTrip = false;
  bool _tripStarted = false;
  bool _isInfoExpanded = false;
  bool _followTruck = true;
  bool _isReRouting = false;
  bool _arrivalShown = false;
  bool _isAutoCameraMoving = false;

  double _currentBearing = 0.0;

  BitmapDescriptor? _stationIcon;
  BitmapDescriptor? _alertIcon;

  LatLng? _currentTruckLatLng;
  LatLng? _previousTruckLatLng;
  StreamSubscription<Position>? _positionStream;

  DateTime? _lastRouteRefreshAt;

  @override
  void initState() {
    super.initState();
    _initializeMap();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  Future<void> _initializeMap() async {
    await _loadIcons();
    await Future.delayed(const Duration(milliseconds: 300));

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      var permission = await Geolocator.checkPermission();

      if (serviceEnabled &&
          (permission == LocationPermission.always ||
              permission == LocationPermission.whileInUse)) {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        _currentTruckLatLng = LatLng(pos.latitude, pos.longitude);
        _refreshMarkers(liveOrigin: _currentTruckLatLng);

        await _loadRoute(
          originLat: pos.latitude,
          originLng: pos.longitude,
          force: true,
        );
        return;
      }

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();

        if (serviceEnabled &&
            (permission == LocationPermission.always ||
                permission == LocationPermission.whileInUse)) {
          final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          );

          _currentTruckLatLng = LatLng(pos.latitude, pos.longitude);
          _refreshMarkers(liveOrigin: _currentTruckLatLng);

          await _loadRoute(
            originLat: pos.latitude,
            originLng: pos.longitude,
            force: true,
          );
          return;
        }
      }
    } catch (_) {}

    await _loadRoute(
      originLat: widget.stationLat,
      originLng: widget.stationLng,
      force: true,
    );
  }

  Future<void> _loadIcons() async {
    try {
      _stationIcon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(64, 64)),
        "assets/responder_pin.png",
      );
    } catch (_) {
      _stationIcon = BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueAzure,
      );
    }

    try {
      _alertIcon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(64, 64)),
        "assets/fire_pin.png",
      );
    } catch (_) {
      _alertIcon = BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueRed,
      );
    }

    if (mounted) setState(() {});
  }

  String _stripHtml(String htmlText) {
    return htmlText
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll("&nbsp;", " ")
        .replaceAll("&amp;", "&")
        .replaceAll("&#39;", "'")
        .replaceAll("&quot;", '"')
        .trim();
  }

  double _calculateBearing(LatLng start, LatLng end) {
    final double lat1 = start.latitude * (pi / 180.0);
    final double lon1 = start.longitude * (pi / 180.0);
    final double lat2 = end.latitude * (pi / 180.0);
    final double lon2 = end.longitude * (pi / 180.0);

    final double dLon = lon2 - lon1;

    final double y = sin(dLon) * cos(lat2);
    final double x =
        cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);

    double bearing = atan2(y, x) * (180.0 / pi);
    bearing = (bearing + 360.0) % 360.0;
    return bearing;
  }

  LatLng _pointAhead(LatLng from, double bearing, double metersAhead) {
    const double earthRadius = 6378137.0;

    final double brng = bearing * pi / 180.0;
    final double lat1 = from.latitude * pi / 180.0;
    final double lon1 = from.longitude * pi / 180.0;
    final double dist = metersAhead / earthRadius;

    final double lat2 = asin(
      sin(lat1) * cos(dist) + cos(lat1) * sin(dist) * cos(brng),
    );

    final double lon2 = lon1 +
        atan2(
          sin(brng) * sin(dist) * cos(lat1),
          cos(dist) - sin(lat1) * sin(lat2),
        );

    return LatLng(lat2 * 180.0 / pi, lon2 * 180.0 / pi);
  }

  Future<void> _animateFrontDrivingCamera(LatLng truckLatLng) async {
    if (_controller == null) return;

    final LatLng frontTarget = _pointAhead(
      truckLatLng,
      _currentBearing,
      28,
    );

    _isAutoCameraMoving = true;
    try {
      await _controller!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: frontTarget,
            zoom: 17.4,
            bearing: _currentBearing,
            tilt: 58,
          ),
        ),
      );
    } finally {
      Future.delayed(const Duration(milliseconds: 500), () {
        _isAutoCameraMoving = false;
      });
    }
  }

  Future<void> _loadRoute({
    required double originLat,
    required double originLng,
    bool force = false,
  }) async {
    if (_isReRouting) return;

    final now = DateTime.now();
    if (!force && _lastRouteRefreshAt != null) {
      final seconds = now.difference(_lastRouteRefreshAt!).inSeconds;
      if (seconds < 3) return;
    }

    _isReRouting = true;
    _lastRouteRefreshAt = now;

    try {
      final origin = "$originLat,$originLng";
      final dest = "${widget.alertLat},${widget.alertLng}";

      final url = Uri.parse(
        "https://maps.googleapis.com/maps/api/directions/json"
        "?origin=$origin"
        "&destination=$dest"
        "&mode=driving"
        "&alternatives=true"
        "&departure_time=now"
        "&traffic_model=best_guess"
        "&key=${widget.apiKey}",
      );

      final response = await http.get(url);
      final data = jsonDecode(response.body);

      if (!mounted) return;

      if (response.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Directions request failed: ${response.statusCode}"),
          ),
        );
        setState(() => _isLoading = false);
        return;
      }

      if (data["status"] != "OK") {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Directions Error: ${data['status']}")),
        );
        setState(() => _isLoading = false);
        return;
      }

      final List routes = data["routes"];

      if (routes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No available route found.")),
        );
        setState(() => _isLoading = false);
        return;
      }

      int bestIndex = 0;
      int shortest = 999999999;

      for (int i = 0; i < routes.length; i++) {
        final int sec = routes[i]["legs"][0]["duration"]["value"];
        if (sec < shortest) {
          shortest = sec;
          bestIndex = i;
        }
      }

      final Set<Polyline> newPolylines = {};
      List<LatLng> bestCoords = [];

      for (int i = 0; i < routes.length; i++) {
        if (i == bestIndex) continue;

        final route = routes[i];
        final String encoded = route["overview_polyline"]["points"];
        final List<PointLatLng> points =
            PolylinePoints().decodePolyline(encoded);

        final List<LatLng> coords =
            points.map((p) => LatLng(p.latitude, p.longitude)).toList();

        newPolylines.add(
          Polyline(
            polylineId: PolylineId("alt_route_$i"),
            color: Colors.grey,
            width: 6,
            zIndex: 1,
            geodesic: true,
            visible: true,
            points: coords,
          ),
        );
      }

      final bestRoute = routes[bestIndex];
      final leg = bestRoute["legs"][0];

      _distance = leg["distance"]?["text"] ?? "";
      _duration = leg["duration"]?["text"] ?? "";
      _remainingDistance = leg["distance"]?["text"] ?? "";
      _remainingDuration =
          leg["duration_in_traffic"]?["text"] ??
          leg["duration"]?["text"] ??
          "";

      final List steps = leg["steps"] ?? [];
      if (steps.isNotEmpty) {
        _nextInstruction = _stripHtml(
          steps.first["html_instructions"] ?? "Continue straight",
        );
      } else {
        _nextInstruction = "Continue straight";
      }

      final String bestEncoded = bestRoute["overview_polyline"]["points"];
      final List<PointLatLng> bestPoints =
          PolylinePoints().decodePolyline(bestEncoded);

      bestCoords =
          bestPoints.map((p) => LatLng(p.latitude, p.longitude)).toList();

      _polylineCoords = bestCoords;

      newPolylines.add(
        Polyline(
          polylineId: const PolylineId("best_route"),
          color: const Color(0xFF1E5BFF),
          width: 7,
          zIndex: 2,
          geodesic: true,
          visible: true,
          points: bestCoords,
        ),
      );

      _polylines = newPolylines;

      _refreshMarkers(
        liveOrigin: _tripStarted && _currentTruckLatLng != null
            ? _currentTruckLatLng
            : null,
      );

      setState(() => _isLoading = false);

      await Future.delayed(const Duration(milliseconds: 250));

      if (!_tripStarted) {
        await _fitCamera();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to load route: $e")),
      );
    } finally {
      _isReRouting = false;
    }
  }

  void _refreshMarkers({LatLng? liveOrigin}) {
    final Set<Marker> updatedMarkers = {
      Marker(
        markerId: const MarkerId("alert"),
        position: LatLng(widget.alertLat, widget.alertLng),
        icon:
            _alertIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
          title: "Fire Location",
          snippet: widget.alertAddress ?? "Incident destination",
        ),
      ),
    };

    // Before trip starts, show station marker.
    // During trip, hide the extra truck marker so the real Google Maps
    // location layer and accuracy circle are the visible live position.
    if (!_tripStarted) {
      updatedMarkers.add(
        Marker(
          markerId: const MarkerId("station"),
          position: LatLng(widget.stationLat, widget.stationLng),
          icon:
              _stationIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(
            title: widget.stationName,
            snippet: widget.stationAddress,
          ),
        ),
      );
    }

    _markers = updatedMarkers;
    if (mounted) setState(() {});
  }

  Future<void> _startTrip() async {
    if (_tripStarted || _isStartingTrip) return;

    setState(() {
      _isStartingTrip = true;
      _arrivalShown = false;
      _followTruck = true;
      _isLoading = true;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Please enable location services first."),
          ),
        );
        setState(() {
          _isStartingTrip = false;
          _isLoading = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Location permission is required to start trip."),
          ),
        );
        setState(() {
          _isStartingTrip = false;
          _isLoading = false;
        });
        return;
      }

      final currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );

      final realLatLng = LatLng(
        currentPosition.latitude,
        currentPosition.longitude,
      );

      _currentTruckLatLng = realLatLng;
      _previousTruckLatLng = realLatLng;
      _tripStarted = true;
      _currentBearing = 0.0;

      _refreshMarkers(liveOrigin: realLatLng);

      await _controller?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: realLatLng,
            zoom: 17.5,
            bearing: 0,
            tilt: 55,
          ),
        ),
      );

      await _loadRoute(
        originLat: currentPosition.latitude,
        originLng: currentPosition.longitude,
        force: true,
      );

      await _animateFrontDrivingCamera(realLatLng);

      _positionStream?.cancel();
      _positionStream =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.bestForNavigation,
              distanceFilter: 1,
            ),
          ).listen((Position position) async {
            final newLatLng = LatLng(position.latitude, position.longitude);

            if (_previousTruckLatLng != null) {
              final distanceMoved = Geolocator.distanceBetween(
                _previousTruckLatLng!.latitude,
                _previousTruckLatLng!.longitude,
                newLatLng.latitude,
                newLatLng.longitude,
              );

              if (distanceMoved >= 0.8) {
                _currentBearing =
                    _calculateBearing(_previousTruckLatLng!, newLatLng);
              }
            }

            _previousTruckLatLng = newLatLng;
            _currentTruckLatLng = newLatLng;

            _refreshMarkers(liveOrigin: newLatLng);

            if (_followTruck) {
              await _animateFrontDrivingCamera(newLatLng);
            }

            await _loadRoute(
              originLat: position.latitude,
              originLng: position.longitude,
            );

            final double metersToDestination = Geolocator.distanceBetween(
              position.latitude,
              position.longitude,
              widget.alertLat,
              widget.alertLng,
            );

            if (metersToDestination <= 30 && !_arrivalShown && mounted) {
              _arrivalShown = true;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Arrived at incident location.")),
              );
            }
          });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Trip started from your current location.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to start trip: $e")),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isStartingTrip = false;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _stopTrip() async {
    await _positionStream?.cancel();
    _positionStream = null;

    setState(() {
      _tripStarted = false;
      _currentTruckLatLng = null;
      _previousTruckLatLng = null;
      _currentBearing = 0.0;
      _followTruck = true;
      _isLoading = true;
      _nextInstruction = "Continue straight";
      _remainingDistance = "";
      _remainingDuration = "";
      _arrivalShown = false;
    });

    _refreshMarkers();

    await _loadRoute(
      originLat: widget.stationLat,
      originLng: widget.stationLng,
      force: true,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Trip stopped.")));
  }

  void _toggleInfoCard() {
    setState(() {
      _isInfoExpanded = !_isInfoExpanded;
    });
  }

  Future<void> _fitCamera() async {
    if (_controller == null) return;

    try {
      if (_polylineCoords.isNotEmpty) {
        double minLat = _polylineCoords.first.latitude;
        double maxLat = minLat;
        double minLng = _polylineCoords.first.longitude;
        double maxLng = minLng;

        for (final p in _polylineCoords) {
          if (p.latitude < minLat) minLat = p.latitude;
          if (p.latitude > maxLat) maxLat = p.latitude;
          if (p.longitude < minLng) minLng = p.longitude;
          if (p.longitude > maxLng) maxLng = p.longitude;
        }

        final bounds = LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        );

        await _controller!.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 80),
        );
      } else {
        final target =
            _currentTruckLatLng ?? LatLng(widget.stationLat, widget.stationLng);

        await _controller!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: target, zoom: 14),
          ),
        );
      }
    } catch (_) {}
  }

  Widget _infoRow(
    IconData icon,
    String label,
    String value, {
    Color iconColor = const Color(0xFFA30000),
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 11.8,
                  height: 1.3,
                ),
                children: [
                  TextSpan(
                    text: "$label: ",
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                  TextSpan(
                    text: value.isEmpty ? "-" : value,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationInstructionCard() {
    if (!_tripStarted) return const SizedBox.shrink();

    return Positioned(
      top: 14,
      left: 12,
      right: 12,
      child: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: const Color(0xFF1E5BFF),
            elevation: 8,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              constraints: const BoxConstraints(minHeight: 58),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E5BFF),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.turn_right_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _nextInstruction.isEmpty
                              ? "Continue straight"
                              : _nextInstruction,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _remainingDistance.isEmpty
                              ? "Navigating"
                              : _remainingDistance,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFollowButton() {
    if (!_tripStarted) return const SizedBox.shrink();

    return Positioned(
      right: 14,
      bottom: 120,
      child: FloatingActionButton(
        heroTag: "follow_btn",
        mini: true,
        backgroundColor: Colors.white,
        elevation: 6,
        onPressed: () async {
          setState(() {
            _followTruck = true;
          });

          if (_currentTruckLatLng != null) {
            await _animateFrontDrivingCamera(_currentTruckLatLng!);
          }
        },
        child: const Icon(
          Icons.navigation,
          color: Color(0xFF1E5BFF),
        ),
      ),
    );
  }

  Widget _tripControls() {
    return Positioned(
      left: 12,
      right: 12,
      bottom: 18,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: (_tripStarted || _isStartingTrip) ? null : _startTrip,
                icon: _isStartingTrip
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                label: Text(
                  _isStartingTrip
                      ? "Starting..."
                      : _tripStarted
                          ? "Trip Started"
                          : "Start Trip",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  disabledBackgroundColor: const Color(0xFF2E7D32),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 5,
                ),
              ),
            ),
            if (_tripStarted) ...[
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _stopTrip,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFA30000),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 5,
                ),
                child: const Icon(
                  Icons.stop_rounded,
                  color: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildExpandableInfoCard() {
    return Positioned(
      top: 12,
      left: 12,
      right: 12,
      child: Material(
        color: Colors.white,
        elevation: 6,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFEAEAEA)),
          ),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: _toggleInfoCard,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.local_fire_department,
                          color: Color(0xFFA30000),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            "Dispatch Navigation",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFA30000),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF6F7FB),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            "${_distance.isEmpty ? '--' : _distance} • ${_duration.isEmpty ? '--' : _duration}",
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          _isInfoExpanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: const Color(0xFFA30000),
                          size: 24,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_isInfoExpanded) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Divider(height: 12, color: Colors.grey.shade300),
                        _infoRow(
                          Icons.home_work_rounded,
                          "Station",
                          widget.stationName,
                        ),
                        _infoRow(
                          Icons.location_on_outlined,
                          "Origin Address",
                          _tripStarted && _currentTruckLatLng != null
                              ? "Current device location"
                              : widget.stationAddress,
                        ),
                        _infoRow(
                          Icons.place_rounded,
                          "Destination",
                          widget.alertAddress ?? "Fire incident location",
                          iconColor: Colors.red,
                        ),
                        _infoRow(
                          Icons.fire_truck_rounded,
                          "Trip Status",
                          _tripStarted ? "On the way" : "Waiting to start",
                          iconColor: _tripStarted
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFFA30000),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final initialPosition = CameraPosition(
      target: _currentTruckLatLng ?? LatLng(widget.stationLat, widget.stationLng),
      zoom: 14,
    );

    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: Colors.white,
        cardColor: Colors.white,
        canvasColor: Colors.white,
        dialogBackgroundColor: Colors.white,
        colorScheme: Theme.of(context).colorScheme.copyWith(surface: Colors.white),
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: const IconThemeData(color: Color(0xFFA30000)),
          leading: IconButton(
            icon: const Icon(
              Icons.chevron_left,
              size: 30,
              color: Color(0xFFA30000),
            ),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            "Navigation Route",
            style: TextStyle(
              color: Color(0xFFA30000),
              fontWeight: FontWeight.bold,
              fontSize: 19,
            ),
          ),
          centerTitle: true,
        ),
        body: Stack(
          children: [
            Container(
              color: Colors.white,
              child: GoogleMap(
                initialCameraPosition: initialPosition,
                markers: _markers,
                polylines: _polylines,
                onMapCreated: (c) => _controller = c,
                onCameraMoveStarted: () {
                  if (_tripStarted && !_isAutoCameraMoving) {
                    setState(() {
                      _followTruck = false;
                    });
                  }
                },
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                mapType: MapType.normal,
                zoomControlsEnabled: false,
                compassEnabled: false,
                tiltGesturesEnabled: true,
                rotateGesturesEnabled: true,
                buildingsEnabled: true,
                trafficEnabled: false,
                indoorViewEnabled: false,
              ),
            ),
            if (!_tripStarted) _buildExpandableInfoCard(),
            _buildNavigationInstructionCard(),
            _buildFollowButton(),
            _tripControls(),
            if (_isLoading)
              Container(
                color: Colors.black.withOpacity(0.10),
                child: const Center(
                  child: Material(
                    color: Colors.white,
                    elevation: 4,
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 16,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                            color: Color(0xFFA30000),
                            strokeWidth: 3,
                          ),
                          SizedBox(height: 10),
                          Text(
                            "Loading route...",
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}