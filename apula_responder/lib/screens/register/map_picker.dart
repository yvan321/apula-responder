import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class MapPickerScreen extends StatefulWidget {
  final String apiKey;
  final String? initialAddress;
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

  static const LatLng _fallbackCenter = LatLng(14.4507, 120.9820);

  LatLng? _pickedLatLng;
  String _pickedAddress = "Tap the map to select your address.";
  bool _loadingAddress = false;
  bool _searchingLocation = false;

  Marker? _marker;
  final TextEditingController _searchController = TextEditingController();

  LatLng get _startCenter {
    if (widget.initialLat != null && widget.initialLng != null) {
      return LatLng(widget.initialLat!, widget.initialLng!);
    }
    return _fallbackCenter;
  }

  @override
  void initState() {
    super.initState();

    final ia = widget.initialAddress?.trim();
    if (ia != null && ia.isNotEmpty) {
      _pickedAddress = ia;
      _searchController.text = ia;
    }

    if (widget.initialLat != null && widget.initialLng != null) {
      _pickedLatLng = LatLng(widget.initialLat!, widget.initialLng!);
      _marker = Marker(
        markerId: const MarkerId("picked"),
        position: _pickedLatLng!,
        infoWindow: const InfoWindow(title: "Selected Address"),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
        _searchController.text = formatted;
        _loadingAddress = false;
      });
    } catch (e) {
      setState(() {
        _pickedAddress = "Failed to get address: $e";
        _loadingAddress = false;
      });
    }
  }

  Future<void> _searchLocation() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter your address to search.")),
      );
      return;
    }

    setState(() {
      _searchingLocation = true;
    });

    final url = Uri.parse(
      "https://maps.googleapis.com/maps/api/geocode/json"
      "?address=${Uri.encodeComponent(query)}"
      "&key=${widget.apiKey}",
    );

    try {
      final res = await http.get(url);
      final data = jsonDecode(res.body);

      if (data["status"] != "OK") {
        final msg = data["error_message"] ?? "Address not found.";
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Search Error: ${data["status"]} - $msg")),
        );
        setState(() {
          _searchingLocation = false;
        });
        return;
      }

      final results = (data["results"] as List<dynamic>? ?? []);
      if (results.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No address found.")),
        );
        setState(() {
          _searchingLocation = false;
        });
        return;
      }

      final location = results[0]["geometry"]["location"];
      final lat = (location["lat"] as num).toDouble();
      final lng = (location["lng"] as num).toDouble();
      final formatted = results[0]["formatted_address"] as String? ?? query;

      final searchedLatLng = LatLng(lat, lng);

      setState(() {
        _pickedLatLng = searchedLatLng;
        _pickedAddress = formatted;
        _marker = Marker(
          markerId: const MarkerId("picked"),
          position: searchedLatLng,
          infoWindow: const InfoWindow(title: "Selected Address"),
        );
        _searchingLocation = false;
      });

      await _controller?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: searchedLatLng, zoom: 16),
        ),
      );
    } catch (e) {
      setState(() {
        _searchingLocation = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to search address: $e")),
      );
    }
  }

  void _onTapMap(LatLng latLng) async {
    setState(() {
      _pickedLatLng = latLng;
      _marker = Marker(
        markerId: const MarkerId("picked"),
        position: latLng,
        infoWindow: const InfoWindow(title: "Selected Address"),
      );
    });

    try {
      await _controller?.animateCamera(CameraUpdate.newLatLng(latLng));
    } catch (_) {}

    await _reverseGeocode(latLng);
  }

  void _confirmSelection() {
    if (_pickedLatLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please tap the map or search your address."),
        ),
      );
      return;
    }

    if (_loadingAddress || _searchingLocation) return;

    Navigator.pop(context, {
      "address": _pickedAddress,
      "lat": _pickedLatLng!.latitude,
      "lng": _pickedLatLng!.longitude,
    });
  }

  @override
  Widget build(BuildContext context) {
    final canConfirm =
        _pickedLatLng != null && !_loadingAddress && !_searchingLocation;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Pick Your Address"),
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
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Column(
              children: [
                Card(
                  elevation: 6,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search, color: Color(0xFFA30000)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => _searchLocation(),
                            decoration: const InputDecoration(
                              hintText: "Search your address...",
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                        _searchingLocation
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : IconButton(
                                onPressed: _searchLocation,
                                icon: const Icon(
                                  Icons.arrow_forward,
                                  color: Color(0xFFA30000),
                                ),
                              ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Card(
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
              ],
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 60,
            child: SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: canConfirm ? _confirmSelection : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFA30000),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFA30000),
                  disabledForegroundColor: Colors.white,
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(
                  Icons.check_circle_outline,
                  color: Colors.white,
                ),
                label: const Text(
                  "Confirm My Address",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}