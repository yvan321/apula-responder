import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:lottie/lottie.dart';

import 'package:apula_responder/screens/register/map_picker.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // ✅ Google API key (use env later if you want)
  static const String _googleApiKey = "AIzaSyC4Ai-W_V2M7qftiuQBYcnyCL8oqaDF680";

  // ✅ REAL PHONE: use your PC IPv4 from ipconfig
  static const String _verificationBaseUrl = "http://192.168.100.10:3005";

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  double? selectedLat;
  double? selectedLng;

  bool _isSubmitting = false; // ✅ loading state

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _contactController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message, Color bgColor) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _register() async {
    if (_isSubmitting) return;

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final contact = _contactController.text.trim();
    final address = _addressController.text.trim();

    if (email.toLowerCase().contains("admin")) {
      _showSnackBar("Admin accounts cannot register in the mobile app.", Colors.red);
      return;
    }

    if (name.isEmpty ||
        email.isEmpty ||
        contact.isEmpty ||
        address.isEmpty ||
        selectedLat == null ||
        selectedLng == null) {
      _showSnackBar("All fields are required and address must be selected on the map.", Colors.red);
      return;
    }

    if (!email.endsWith("@gmail.com")) {
      _showSnackBar("Email must be a Gmail address.", Colors.red);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final code = (100000 + Random().nextInt(900000)).toString();

      // ✅ 1) Save to Firestore
      await FirebaseFirestore.instance.collection('users').add({
        'name': name,
        'email': email,
        'contact': contact,
        'address': address,
        'latitude': selectedLat,
        'longitude': selectedLng,
        'role': 'responder',
        'platform': 'mobile',
        'verificationCode': code,
        'verified': false,
        'approved': false,
        'status': "Unavailable",
        'smsOptIn': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      // ✅ 2) Send verification email (REAL PHONE -> PC IPv4)
      final url = Uri.parse("$_verificationBaseUrl/send-verification");

      final response = await http
          .post(
            url,
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"email": email, "code": code}),
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode == 200) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogCtx) {
            Future.delayed(const Duration(seconds: 2), () {
              if (!mounted) return;
              Navigator.of(dialogCtx).pop(); // close dialog safely
              Navigator.of(context).pushReplacementNamed(
                '/verification',
                arguments: email,
              );
            });

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 200,
                    width: 400,
                    child: Lottie.asset(
                      'assets/check orange.json',
                      repeat: false,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "Check your email for the verification code!",
                    textAlign: TextAlign.center,
                    style: TextStyle(
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
      } else {
        _showSnackBar(
          "Failed to send verification email (${response.statusCode}): ${response.body}",
          Colors.red,
        );
      }
    } on TimeoutException {
      _showSnackBar("Request timeout: phone cannot reach PC server.", Colors.red);
    } on SocketException catch (e) {
      _showSnackBar("Network error: ${e.message}", Colors.red);
    } catch (e) {
      _showSnackBar("Something went wrong: $e", Colors.red);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: _isSubmitting ? null : () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(30),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(shape: BoxShape.circle),
                  child: Icon(
                    Icons.chevron_left,
                    size: 30,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "Create your account",
                style: TextStyle(
                  color: Color(0xFFA30000),
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 40),

              TextField(
                controller: _nameController,
                decoration: _input("Full Name"),
              ),
              const SizedBox(height: 20),

              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: _input("Email"),
              ),
              const SizedBox(height: 20),

              TextField(
                controller: _contactController,
                keyboardType: TextInputType.phone,
                decoration: _input("Contact Number"),
              ),
              const SizedBox(height: 20),

              // Address (MAP PICKER)
              TextField(
                controller: _addressController,
                readOnly: true,
                decoration: _input("Select Station Address (Tap to Open Map)")
                    .copyWith(suffixIcon: const Icon(Icons.map)),
                onTap: _isSubmitting
                    ? null
                    : () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MapPickerScreen(apiKey: _googleApiKey),
                          ),
                        );

                        if (!mounted) return;

                        if (result != null && result is Map<String, dynamic>) {
                          setState(() {
                            _addressController.text = (result["address"] ?? "").toString();
                            selectedLat = (result["lat"] as num?)?.toDouble();
                            selectedLng = (result["lng"] as num?)?.toDouble();
                          });
                        }
                      },
              ),

              const SizedBox(height: 40),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _isSubmitting ? null : _register,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          "Register",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _input(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    );
  }
}