// lib/screens/app/map/map_navigation_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:http/http.dart' as http;

class MapNavigationPage extends StatefulWidget {
  final double responderLat;
  final double responderLng;
  final double alertLat;
  final double alertLng;
  final String apiKey;

  const MapNavigationPage({
    super.key,
    required this.responderLat,
    required this.responderLng,
    required this.alertLat,
    required this.alertLng,
    required this.apiKey,
  });

  @override
  State<MapNavigationPage> createState() => _MapNavigationPageState();
}

class _MapNavigationPageState extends State<MapNavigationPage> {
  GoogleMapController? _controller;

  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  List<LatLng> _polylineCoords = [];

  String _distance = "";
  String _duration = "";

  BitmapDescriptor? _responderIcon;
  BitmapDescriptor? _alertIcon;

  @override
  void initState() {
    super.initState();
    _loadIcons();
    Future.delayed(const Duration(milliseconds: 300), _loadRoute);
  }

  // ---------------------------------------------------------------------------
  // LOAD CUSTOM MARKERS
  // ---------------------------------------------------------------------------
  Future<void> _loadIcons() async {
    // 🚒 Responder logo icon
    _responderIcon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(size: Size(64, 64)),
      "assets/responder_pin.png",
    );

    // 🔥 Fire alert icon
    _alertIcon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(size: Size(64, 64)),
      "assets/fire_pin.png",
    );

    setState(() {});
  }

  // ---------------------------------------------------------------------------
  // LOAD ROUTE USING GOOGLE MAPS DIRECTIONS API
  // ---------------------------------------------------------------------------
  Future<void> _loadRoute() async {
    final origin = "${widget.responderLat},${widget.responderLng}";
    final dest = "${widget.alertLat},${widget.alertLng}";

    final url = Uri.parse(
      "https://maps.googleapis.com/maps/api/directions/json"
      "?origin=$origin&destination=$dest&mode=driving&alternatives=true&key=${widget.apiKey}",
    );

    final response = await http.get(url);
    final data = jsonDecode(response.body);

    if (data["status"] != "OK") {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Directions Error: ${data['status']}")),
      );
      return;
    }

    // Choose fastest route
    List routes = data["routes"];
    int bestIndex = 0;
    int shortest = 999999999;

    for (int i = 0; i < routes.length; i++) {
      int sec = routes[i]["legs"][0]["duration"]["value"];
      if (sec < shortest) {
        shortest = sec;
        bestIndex = i;
      }
    }

    var route = routes[bestIndex];
    _distance = route["legs"][0]["distance"]["text"];
    _duration = route["legs"][0]["duration"]["text"];

    // Decode polyline
    String encoded = route["overview_polyline"]["points"];
    List<PointLatLng> points = PolylinePoints().decodePolyline(encoded);

    _polylineCoords =
        points.map((p) => LatLng(p.latitude, p.longitude)).toList();

    _polylines = {
      Polyline(
        polylineId: const PolylineId("route"),
        color: Colors.blue,
        width: 6,
        points: _polylineCoords,
      ),
    };

    // Markers
    _markers = {
      Marker(
        markerId: const MarkerId("responder"),
        position: LatLng(widget.responderLat, widget.responderLng),
        icon: _responderIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: "Responder"),
      ),
      Marker(
        markerId: const MarkerId("alert"),
        position: LatLng(widget.alertLat, widget.alertLng),
        icon: _alertIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: "Fire Location"),
      ),
    };

    setState(() {});
    await Future.delayed(const Duration(milliseconds: 300));
    _fitCamera();
  }

  // ---------------------------------------------------------------------------
  // FIT MAP CAMERA BOUNDS
  // ---------------------------------------------------------------------------
  Future<void> _fitCamera() async {
    if (_controller == null || _polylineCoords.isEmpty) return;

    double minLat = _polylineCoords.first.latitude;
    double maxLat = minLat;
    double minLng = _polylineCoords.first.longitude;
    double maxLng = minLng;

    for (var p in _polylineCoords) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    LatLngBounds bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    try {
      await _controller!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 80),
      );
    } catch (e) {}
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left,
              size: 32, color: Color(0xFFA30000)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Navigation Route",
          style: TextStyle(
            color: Color(0xFFA30000),
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        centerTitle: true,
      ),

      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(widget.responderLat, widget.responderLng),
              zoom: 14,
            ),
            markers: _markers,
            polylines: _polylines,
            onMapCreated: (c) => _controller = c,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            mapType: MapType.normal,
          ),

          // TOP INFO BOX
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: Card(
              elevation: 6,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.directions_car, color: Colors.red),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Distance: $_distance",
                            style: const TextStyle(
                                fontWeight: FontWeight.bold)),
                        Text("ETA: $_duration",
                            style: const TextStyle(color: Colors.black54)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
