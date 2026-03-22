// lib/screens/app/map/map_navigation_page.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

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
  bool _isLoading = true;
  bool _isStartingTrip = false;
  bool _tripStarted = false;
  bool _isInfoExpanded = false;

  BitmapDescriptor? _stationIcon;
  BitmapDescriptor? _alertIcon;
  BitmapDescriptor? _truckIcon;

  LatLng? _currentTruckLatLng;
  StreamSubscription<Position>? _positionStream;

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
    await _loadRoute(
      originLat: widget.stationLat,
      originLng: widget.stationLng,
    );
  }

  Future<void> _loadIcons() async {
    try {
      _stationIcon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(64, 64)),
        "assets/responder_pin.png",
      );
    } catch (_) {
      _stationIcon =
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
    }

    try {
      _alertIcon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(64, 64)),
        "assets/fire_pin.png",
      );
    } catch (_) {
      _alertIcon =
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
    }

    try {
      _truckIcon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(84, 84)),
        "assets/firetruck_pin.png",
      );
    } catch (_) {
      _truckIcon =
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
    }

    if (mounted) setState(() {});
  }

  Future<void> _loadRoute({
    required double originLat,
    required double originLng,
  }) async {
    try {
      final origin = "$originLat,$originLng";
      final dest = "${widget.alertLat},${widget.alertLng}";

      final url = Uri.parse(
        "https://maps.googleapis.com/maps/api/directions/json"
        "?origin=$origin&destination=$dest&mode=driving&alternatives=true&key=${widget.apiKey}",
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

      final route = routes[bestIndex];
      _distance = route["legs"][0]["distance"]["text"] ?? "";
      _duration = route["legs"][0]["duration"]["text"] ?? "";

      final String encoded = route["overview_polyline"]["points"];
      final List<PointLatLng> points = PolylinePoints().decodePolyline(encoded);

      _polylineCoords =
          points.map((p) => LatLng(p.latitude, p.longitude)).toList();

      _polylines = {
        Polyline(
          polylineId: const PolylineId("route"),
          color: const Color(0xFF1565C0),
          width: 6,
          points: _polylineCoords,
        ),
      };

      _refreshMarkers(
        liveOrigin: _tripStarted && _currentTruckLatLng != null
            ? _currentTruckLatLng
            : null,
      );

      setState(() => _isLoading = false);

      await Future.delayed(const Duration(milliseconds: 300));
      await _fitCamera();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to load route: $e")),
      );
    }
  }

  void _refreshMarkers({LatLng? liveOrigin}) {
    final Set<Marker> updatedMarkers = {
      Marker(
        markerId: const MarkerId("alert"),
        position: LatLng(widget.alertLat, widget.alertLng),
        icon: _alertIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
          title: "Fire Location",
          snippet: widget.alertAddress ?? "Incident destination",
        ),
      ),
    };

    if (liveOrigin != null) {
      updatedMarkers.add(
        Marker(
          markerId: const MarkerId("truck"),
          position: liveOrigin,
          icon: _truckIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          anchor: const Offset(0.5, 0.5),
          flat: true,
          infoWindow: const InfoWindow(
            title: "Fire Truck",
            snippet: "Live responding unit",
          ),
        ),
      );
    } else {
      updatedMarkers.add(
        Marker(
          markerId: const MarkerId("station"),
          position: LatLng(widget.stationLat, widget.stationLng),
          icon: _stationIcon ??
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

    setState(() => _isStartingTrip = true);

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Please enable location services first."),
          ),
        );
        setState(() => _isStartingTrip = false);
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
        setState(() => _isStartingTrip = false);
        return;
      }

      final currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );

      _currentTruckLatLng = LatLng(
        currentPosition.latitude,
        currentPosition.longitude,
      );

      _tripStarted = true;
      _isLoading = true;

      _refreshMarkers(liveOrigin: _currentTruckLatLng);

      await _loadRoute(
        originLat: currentPosition.latitude,
        originLng: currentPosition.longitude,
      );

      await _controller?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: _currentTruckLatLng!,
            zoom: 16,
          ),
        ),
      );

      _positionStream?.cancel();
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 5,
        ),
      ).listen((Position position) async {
        final newLatLng = LatLng(position.latitude, position.longitude);
        _currentTruckLatLng = newLatLng;

        _refreshMarkers(liveOrigin: newLatLng);

        await _controller?.animateCamera(
          CameraUpdate.newLatLng(newLatLng),
        );

        await _loadRoute(
          originLat: position.latitude,
          originLng: position.longitude,
        );
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Trip started. Fire truck is now live.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to start trip: $e")),
      );
    } finally {
      if (mounted) {
        setState(() => _isStartingTrip = false);
      }
    }
  }

  Future<void> _stopTrip() async {
    await _positionStream?.cancel();
    _positionStream = null;

    setState(() {
      _tripStarted = false;
      _currentTruckLatLng = null;
      _isLoading = true;
    });

    _refreshMarkers();

    await _loadRoute(
      originLat: widget.stationLat,
      originLng: widget.stationLng,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Trip stopped.")),
    );
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
            CameraPosition(
              target: target,
              zoom: 14,
            ),
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

  Widget _tripControls() {
    return Positioned(
      bottom: 20,
      left: 14,
      right: 14,
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
                  fontSize: 15,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                disabledBackgroundColor: const Color(0xFF2E7D32),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                elevation: 3,
              ),
            ),
          ),
          if (_tripStarted) ...[
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _stopTrip,
                icon: const Icon(
                  Icons.stop_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                label: const Text(
                  "Stop Trip",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFA30000),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  elevation: 3,
                ),
              ),
            ),
          ],
        ],
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
                        Divider(
                          height: 12,
                          color: Colors.grey.shade300,
                        ),
                        _infoRow(
                          Icons.home_work_rounded,
                          "Station",
                          widget.stationName,
                        ),
                        _infoRow(
                          Icons.location_on_outlined,
                          "Origin Address",
                          widget.stationAddress,
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
      target: LatLng(widget.stationLat, widget.stationLng),
      zoom: 14,
    );

    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: Colors.white,
        cardColor: Colors.white,
        canvasColor: Colors.white,
        dialogBackgroundColor: Colors.white,
        colorScheme: Theme.of(context).colorScheme.copyWith(
              surface: Colors.white,
            ),
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
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
                mapType: MapType.normal,
                zoomControlsEnabled: false,
              ),
            ),
            _buildExpandableInfoCard(),
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