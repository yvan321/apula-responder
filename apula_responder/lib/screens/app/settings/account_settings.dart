import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:apula_responder/screens/register/map_picker.dart';

class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({super.key});

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  // ✅ Put your key here for now (or move to env later)
  static const String _googleApiKey = "AIzaSyC4Ai-W_V2M7qftiuQBYcnyCL8oqaDF680";

  final _nameController = TextEditingController();
  final _contactController = TextEditingController();
  final _stationController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = true;
  String? _docId;

  double? selectedLat;
  double? selectedLng;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _stationController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    final query = await FirebaseFirestore.instance
        .collection("users")
        .where("email", isEqualTo: user.email)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      final doc = query.docs.first;
      final data = doc.data();
      _docId = doc.id;

      final latVal = data["latitude"];
      final lngVal = data["longitude"];

      setState(() {
        _nameController.text = (data["name"] ?? "").toString();
        _contactController.text = (data["contact"] ?? "").toString();
        _stationController.text = (data["address"] ?? "").toString();

        // ✅ safe numeric cast
        selectedLat = (latVal is num) ? latVal.toDouble() : null;
        selectedLng = (lngVal is num) ? lngVal.toDouble() : null;

        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveChanges() async {
    final name = _nameController.text.trim();
    final contact = _contactController.text.trim();
    final station = _stationController.text.trim();
    final pass = _passwordController.text.trim();
    final confirm = _confirmPasswordController.text.trim();

    if (name.isEmpty || contact.isEmpty || station.isEmpty) {
      _showSnackBar("Please fill in all required fields.", Colors.red);
      return;
    }

    // ✅ Require map selection if your app needs coordinates
    if (selectedLat == null || selectedLng == null) {
      _showSnackBar("Please select an address on the map.", Colors.red);
      return;
    }

    if (pass.isNotEmpty && pass != confirm) {
      _showSnackBar("Passwords do not match.", Colors.red);
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _loadingDialog("Saving changes..."),
    );

    try {
      if (_docId != null) {
        await FirebaseFirestore.instance.collection("users").doc(_docId).update({
          "name": name,
          "contact": contact,
          "address": station,
          "latitude": selectedLat,
          "longitude": selectedLng,
          "updatedAt": FieldValue.serverTimestamp(),
        });
      }

      if (pass.isNotEmpty) {
        await FirebaseAuth.instance.currentUser!.updatePassword(pass);
      }

      Navigator.pop(context); // close loading dialog
      _showSuccessDialog("Changes saved successfully!");
    } catch (e) {
      Navigator.pop(context); // close loading dialog
      _showSnackBar("Error: $e", Colors.red);
    }
  }

  void _showSnackBar(String message, Color bgColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _loadingDialog(String msg) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Lottie.asset('assets/fireloading.json', width: 130, height: 130),
          const SizedBox(height: 20),
          Text(
            msg,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFA30000),
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog(String msg) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        Future.delayed(const Duration(seconds: 2), () {
          Navigator.pop(context); // close success dialog
          Navigator.pop(context); // back
        });

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Lottie.asset(
                'assets/check orange.json',
                width: 150,
                height: 150,
                repeat: false,
              ),
              const SizedBox(height: 20),
              Text(
                msg,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFA30000),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const redColor = Color(0xFFA30000);

    return Scaffold(
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: redColor))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 10, top: 10),
                    child: InkWell(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.chevron_left, size: 30, color: redColor),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                    child: Text(
                      "Account Settings",
                      style: TextStyle(
                        color: redColor,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            TextField(
                              controller: _nameController,
                              decoration: _input("Name"),
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              controller: _contactController,
                              decoration: _input("Contact Number"),
                            ),
                            const SizedBox(height: 20),

                            // ⭐ MAP PICKER HERE (FIXED)
                            TextField(
                              controller: _stationController,
                              readOnly: true,
                              decoration: _input("Address").copyWith(
                                suffixIcon: const Icon(Icons.map),
                              ),
                              onTap: () async {
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => MapPickerScreen(
                                      apiKey: _googleApiKey,
                                      initialAddress: _stationController.text,
                                      initialLat: selectedLat,
                                      initialLng: selectedLng,
                                    ),
                                  ),
                                );

                                if (result != null && result is Map<String, dynamic>) {
                                  setState(() {
                                    _stationController.text =
                                        (result["address"] ?? "").toString();
                                    selectedLat = (result["lat"] as num?)?.toDouble();
                                    selectedLng = (result["lng"] as num?)?.toDouble();
                                  });
                                }
                              },
                            ),

                            const SizedBox(height: 20),
                            TextField(
                              controller: _passwordController,
                              obscureText: true,
                              decoration: _input("New Password (optional)"),
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              controller: _confirmPasswordController,
                              obscureText: true,
                              decoration: _input("Confirm Password"),
                            ),
                            const SizedBox(height: 30),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                onPressed: _saveChanges,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: redColor,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: const Text(
                                  "Save Changes",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  InputDecoration _input(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }
}