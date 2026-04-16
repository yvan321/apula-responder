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
  bool _drivingMode = false;

  double _currentBearing = 0.0;
  double _currentSpeedKph = 0.0;
  double _gpsAccuracyMeters = 0.0;

  BitmapDescriptor? _stationIcon;
  BitmapDescriptor? _alertIcon;

  LatLng? _currentTruckLatLng;
  LatLng? _previousTruckLatLng;
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<ServiceStatus>? _serviceStatusStream;

  DateTime? _lastRouteRefreshAt;

  @override
  void initState() {
    super.initState();
    _initializeMap();
    _listenLocationServiceChanges();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _serviceStatusStream?.cancel();
    super.dispose();
  }

  void _listenLocationServiceChanges() {
    _serviceStatusStream =
        Geolocator.getServiceStatusStream().listen((ServiceStatus status) async {
      if (status == ServiceStatus.enabled && !_tripStarted) {
        final latLng = await _getBestCurrentLatLng();
        if (latLng != null) {
          _currentTruckLatLng = latLng;
          _refreshMarkers();

          await _controller?.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: latLng,
                zoom: 17,
              ),
            ),
          );

          await _loadRoute(
            originLat: latLng.latitude,
            originLng: latLng.longitude,
            force: true,
          );
        }
      }
    });
  }

  Future<void> _initializeMap() async {
    await _loadIcons();
    await Future.delayed(const Duration(milliseconds: 300));

    final LatLng? realLocation = await _getBestCurrentLatLng();

    if (realLocation != null) {
      _currentTruckLatLng = realLocation;
      _refreshMarkers();

      await _loadRoute(
        originLat: realLocation.latitude,
        originLng: realLocation.longitude,
        force: true,
      );

      await Future.delayed(const Duration(milliseconds: 250));
      await _controller?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: realLocation,
            zoom: 17,
          ),
        ),
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    _refreshMarkers();

    await _loadRoute(
      originLat: widget.stationLat,
      originLng: widget.stationLng,
      force: true,
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<LatLng?> _getBestCurrentLatLng() async {
    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      Position? best;

      try {
        final current = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.bestForNavigation,
          timeLimit: const Duration(seconds: 12),
        );
        best = current;
      } catch (_) {}

      try {
        final refined = await _waitForVeryAccuratePosition(
          targetAccuracyMeters: 12,
          timeout: const Duration(seconds: 20),
        );
        best = _pickBetterPosition(best, refined);
      } catch (_) {}

      if (best == null) return null;

      if (best.accuracy <= 0 || best.accuracy > 35) {
        return null;
      }

      return LatLng(best.latitude, best.longitude);
    } catch (_) {
      return null;
    }
  }

  Future<Position> _waitForVeryAccuratePosition({
    required double targetAccuracyMeters,
    required Duration timeout,
  }) async {
    final completer = Completer<Position>();
    StreamSubscription<Position>? sub;
    Timer? timer;
    Position? bestSeen;

    timer = Timer(timeout, () async {
      await sub?.cancel();
      if (!completer.isCompleted) {
        if (bestSeen != null) {
          completer.complete(bestSeen!);
        } else {
          completer.completeError(
            TimeoutException("No accurate GPS position received."),
          );
        }
      }
    });

    sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      ),
    ).listen(
      (Position position) async {
        if (position.latitude == 0 && position.longitude == 0) {
          return;
        }

        bestSeen = _pickBetterPosition(bestSeen, position);

        final double accuracy = position.accuracy;
        if (accuracy > 0 && accuracy <= targetAccuracyMeters) {
          await sub?.cancel();
          timer?.cancel();
          if (!completer.isCompleted) {
            completer.complete(position);
          }
        }
      },
      onError: (error) async {
        await sub?.cancel();
        timer?.cancel();
        if (!completer.isCompleted) {
          if (bestSeen != null) {
            completer.complete(bestSeen!);
          } else {
            completer.completeError(error);
          }
        }
      },
    );

    return completer.future;
  }

  Position _pickBetterPosition(Position? a, Position b) {
    if (a == null) return b;

    final bool bHasAccuracy = b.accuracy > 0;
    final bool aHasAccuracy = a.accuracy > 0;

    if (bHasAccuracy && !aHasAccuracy) return b;
    if (!bHasAccuracy && aHasAccuracy) return a;

    if (bHasAccuracy && aHasAccuracy) {
      if (b.accuracy < a.accuracy) return b;
      if (a.accuracy < b.accuracy) return a;
    }

    final aTime = a.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bTime = b.timestamp ?? DateTime.now();

    return bTime.isAfter(aTime) ? b : a;
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
      _drivingMode ? 36 : 28,
    );

    _isAutoCameraMoving = true;
    try {
      await _controller!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: _drivingMode ? frontTarget : truckLatLng,
            zoom: _drivingMode ? 18.2 : 17.4,
            bearing: _drivingMode ? _currentBearing : 0,
            tilt: _drivingMode ? 68 : 58,
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
            visible: !_drivingMode,
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
          width: _drivingMode ? 9 : 7,
          zIndex: 2,
          geodesic: true,
          visible: true,
          points: bestCoords,
        ),
      );

      _polylines = newPolylines;

      _refreshMarkers();

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

  void _refreshMarkers() {
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

    if (!_tripStarted && !_drivingMode) {
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
      _drivingMode = true;
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

      final LatLng? realLatLng = await _getBestCurrentLatLng();

      if (realLatLng == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Unable to get accurate GPS location. Go outside or enable precise location.",
            ),
          ),
        );
        setState(() {
          _isStartingTrip = false;
          _isLoading = false;
        });
        return;
      }

      _currentTruckLatLng = realLatLng;
      _previousTruckLatLng = realLatLng;
      _tripStarted = true;
      _currentBearing = 0.0;
      _currentSpeedKph = 0.0;

      _refreshMarkers();

      await _controller?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: realLatLng,
            zoom: 18.2,
            bearing: 0,
            tilt: 68,
          ),
        ),
      );

      await _loadRoute(
        originLat: realLatLng.latitude,
        originLng: realLatLng.longitude,
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
            if (position.latitude == 0 && position.longitude == 0) return;
            if (position.accuracy > 0 && position.accuracy > 35) return;

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
            _gpsAccuracyMeters = position.accuracy;
            _currentSpeedKph =
                position.speed > 0 ? position.speed * 3.6 : 0.0;

            if (mounted) {
              setState(() {});
            }

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
        const SnackBar(content: Text("Driving mode started.")),
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
      _currentSpeedKph = 0.0;
      _gpsAccuracyMeters = 0.0;
      _drivingMode = false;
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
        child: Material(
          color: const Color(0xFF1E5BFF),
          elevation: 10,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E5BFF),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.turn_right_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _nextInstruction.isEmpty
                            ? "Continue straight"
                            : _nextInstruction,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _smallStatChip(
                            icon: Icons.route_rounded,
                            text: _remainingDistance.isEmpty
                                ? "Navigating"
                                : _remainingDistance,
                          ),
                          _smallStatChip(
                            icon: Icons.schedule_rounded,
                            text: _remainingDuration.isEmpty
                                ? "--"
                                : _remainingDuration,
                          ),
                          _smallStatChip(
                            icon: Icons.speed_rounded,
                            text: "${_currentSpeedKph.round()} km/h",
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _smallStatChip({
    required IconData icon,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFollowButton() {
    if (!_tripStarted) return const SizedBox.shrink();

    return Positioned(
      right: 14,
      bottom: 180,
      child: Column(
        children: [
          FloatingActionButton(
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
            child: Icon(
              _followTruck ? Icons.my_location : Icons.navigation,
              color: const Color(0xFF1E5BFF),
            ),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: "drive_mode_btn",
            mini: true,
            backgroundColor: _drivingMode
                ? const Color(0xFF1E5BFF)
                : Colors.white,
            elevation: 6,
            onPressed: () async {
              setState(() {
                _drivingMode = !_drivingMode;
              });

              if (_currentTruckLatLng != null) {
                await _animateFrontDrivingCamera(_currentTruckLatLng!);
              }

              await _loadRoute(
                originLat: (_currentTruckLatLng?.latitude ?? widget.stationLat),
                originLng: (_currentTruckLatLng?.longitude ?? widget.stationLng),
                force: true,
              );
            },
            child: Icon(
              Icons.directions_car_rounded,
              color: _drivingMode ? Colors.white : const Color(0xFF1E5BFF),
            ),
          ),
        ],
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_tripStarted && _drivingMode)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.10),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _bottomDriveInfo(
                        label: "ETA",
                        value: _remainingDuration.isEmpty ? "--" : _remainingDuration,
                      ),
                    ),
                    Expanded(
                      child: _bottomDriveInfo(
                        label: "DISTANCE",
                        value: _remainingDistance.isEmpty ? "--" : _remainingDistance,
                      ),
                    ),
                    Expanded(
                      child: _bottomDriveInfo(
                        label: "GPS",
                        value: _gpsAccuracyMeters > 0
                            ? "${_gpsAccuracyMeters.round()} m"
                            : "--",
                      ),
                    ),
                  ],
                ),
              ),
            Row(
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
                              ? "Driving Mode Active"
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
          ],
        ),
      ),
    );
  }

  Widget _bottomDriveInfo({
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.black54,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
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
                          _currentTruckLatLng != null
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
          title: Text(
            _drivingMode ? "Driving Mode" : "Navigation Route",
            style: const TextStyle(
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
                onMapCreated: (c) async {
                  _controller = c;

                  final LatLng target =
                      _currentTruckLatLng ??
                      LatLng(widget.stationLat, widget.stationLng);

                  await _controller?.animateCamera(
                    CameraUpdate.newCameraPosition(
                      CameraPosition(
                        target: target,
                        zoom: _currentTruckLatLng != null ? 17 : 14,
                      ),
                    ),
                  );
                },
                onCameraMoveStarted: () {
                  if (_tripStarted && !_isAutoCameraMoving) {
                    setState(() {
                      _followTruck = false;
                    });
                  }
                },
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
                mapType: MapType.normal,
                zoomControlsEnabled: false,
                compassEnabled: false,
                tiltGesturesEnabled: true,
                rotateGesturesEnabled: true,
                buildingsEnabled: true,
                trafficEnabled: true,
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