// lib/screens/register/map_picker.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class MapPickerScreen extends StatefulWidget {
  final String apiKey;

  // ✅ so account_settings.dart can pass initialAddress:
  final String? initialAddress;

  // ✅ optional: if you want to open the map on the saved location
  final double? initialLat;
  final double? initialLng;

  const MapPickerScreen({
    super.key,
    required this.apiKey,
    this.initialAddress,
    this.initialLat,
    this.initialLng,
  });

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  GoogleMapController? _controller;

  // Default fallback center (change if you want)
  static const LatLng _fallbackCenter = LatLng(14.4507, 120.9820);

  LatLng? _pickedLatLng;
  String _pickedAddress = "Tap the map to select a location.";
  bool _loadingAddress = false;

  Marker? _marker;

  LatLng get _startCenter {
    if (widget.initialLat != null && widget.initialLng != null) {
      return LatLng(widget.initialLat!, widget.initialLng!);
    }
    return _fallbackCenter;
  }

  @override
  void initState() {
    super.initState();

    // Prefill address if provided
    final ia = widget.initialAddress?.trim();
    if (ia != null && ia.isNotEmpty) {
      _pickedAddress = ia;
    }

    // Prefill marker if coordinates provided
    if (widget.initialLat != null && widget.initialLng != null) {
      _pickedLatLng = LatLng(widget.initialLat!, widget.initialLng!);
      _marker = Marker(
        markerId: const MarkerId("picked"),
        position: _pickedLatLng!,
        infoWindow: const InfoWindow(title: "Selected Location"),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Reverse geocode: LatLng -> formatted address (Google Geocoding API)
  // ---------------------------------------------------------------------------
  Future<void> _reverseGeocode(LatLng latLng) async {
    setState(() {
      _loadingAddress = true;
      _pickedAddress = "Getting address...";
    });

    final url = Uri.parse(
      "https://maps.googleapis.com/maps/api/geocode/json"
      "?latlng=${latLng.latitude},${latLng.longitude}"
      "&key=${widget.apiKey}",
    );

    try {
      final res = await http.get(url);
      final data = jsonDecode(res.body);

      if (data["status"] != "OK") {
        final msg = data["error_message"] ?? "Unknown error";
        setState(() {
          _pickedAddress = "Geocoding Error: ${data["status"]} - $msg";
          _loadingAddress = false;
        });
        return;
      }

      final results = (data["results"] as List<dynamic>? ?? []);
      final formatted = results.isNotEmpty
          ? (results[0]["formatted_address"] as String? ??
                "No formatted address found.")
          : "No address found for this location.";

      setState(() {
        _pickedAddress = formatted;
        _loadingAddress = false;
      });
    } catch (e) {
      setState(() {
        _pickedAddress = "Failed to get address: $e";
        _loadingAddress = false;
      });
    }
  }

  void _onTapMap(LatLng latLng) async {
    setState(() {
      _pickedLatLng = latLng;
      _marker = Marker(
        markerId: const MarkerId("picked"),
        position: latLng,
        infoWindow: const InfoWindow(title: "Selected Location"),
      );
    });

    // Move camera to the tapped point
    try {
      await _controller?.animateCamera(CameraUpdate.newLatLng(latLng));
    } catch (_) {}

    await _reverseGeocode(latLng);
  }

  void _confirmSelection() {
    if (_pickedLatLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please tap the map to pick a location.")),
      );
      return;
    }

    if (_loadingAddress) return;

    // Return exactly what your RegisterScreen expects
    Navigator.pop(context, {
      "address": _pickedAddress,
      "lat": _pickedLatLng!.latitude,
      "lng": _pickedLatLng!.longitude,
    });
  }

  @override
  Widget build(BuildContext context) {
    final canConfirm = _pickedLatLng != null && !_loadingAddress;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Pick Station Address"),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _startCenter,
              zoom: 14,
            ),
            onMapCreated: (c) => _controller = c,
            onTap: _onTapMap,
            markers: {if (_marker != null) _marker!},
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            mapType: MapType.normal,
          ),

          // TOP INFO BOX (Address preview)
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.place, color: Colors.red),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _pickedAddress,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    if (_loadingAddress) ...[
                      const SizedBox(width: 10),
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // CONFIRM BUTTON
          Positioned(
            left: 16,
            right: 16,
            bottom: 60,
            child: SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: canConfirm ? _confirmSelection : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFA30000), // 🔴 Red background
                  foregroundColor: Colors.white, // ⚪ White text & icon
                  disabledBackgroundColor:
                      Colors.red.shade200, // Optional disabled color
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                label: const Text(
                  "Confirm Address",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
