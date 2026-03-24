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
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static const String _googleApiKey = "AIzaSyC4Ai-W_V2M7qftiuQBYcnyCL8oqaDF680";

  static const String _verificationUrl =
      "https://apula-web.vercel.app/api/send-verification";

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  double? selectedLat;
  double? selectedLng;

  bool _isSubmitting = false;

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
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
          ),
        ),
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  bool _isValidPhilippineNumber(String number) {
    final cleaned = number.replaceAll(RegExp(r'[\s-]+'), '');
    return RegExp(r'^(09\d{9}|\+639\d{9}|639\d{9})$').hasMatch(cleaned);
  }

  String _normalizePhone(String number) {
    String cleaned = number.replaceAll(RegExp(r'[\s-]+'), '');

    if (cleaned.startsWith('+63')) {
      cleaned = '0${cleaned.substring(3)}';
    } else if (cleaned.startsWith('63')) {
      cleaned = '0${cleaned.substring(2)}';
    }

    return cleaned;
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _getUserByEmail(
    String email,
  ) async {
    final result = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();

    if (result.docs.isEmpty) return null;
    return result.docs.first;
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _getUserByContact(
    String contact,
  ) async {
    final result = await FirebaseFirestore.instance
        .collection('users')
        .where('contact', isEqualTo: contact)
        .limit(1)
        .get();

    if (result.docs.isEmpty) return null;
    return result.docs.first;
  }

  Future<void> _register() async {
    if (_isSubmitting) return;

    FocusScope.of(context).unfocus();

    final name = _nameController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final rawContact = _contactController.text.trim();
    final contact = _normalizePhone(rawContact);
    final address = _addressController.text.trim();

    if (email.contains("admin")) {
      _showSnackBar(
        "Admin accounts cannot register in the mobile app.",
        Colors.red,
      );
      return;
    }

    if (name.isEmpty ||
        email.isEmpty ||
        rawContact.isEmpty ||
        address.isEmpty ||
        selectedLat == null ||
        selectedLng == null) {
      _showSnackBar(
        "All fields are required and address must be selected on the map.",
        Colors.red,
      );
      return;
    }

    if (!email.endsWith("@gmail.com")) {
      _showSnackBar("Email must be a Gmail address.", Colors.red);
      return;
    }

    if (!_isValidPhilippineNumber(rawContact)) {
      _showSnackBar("Enter a valid Philippine contact number.", Colors.red);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final existingEmailUser = await _getUserByEmail(email);
      final existingContactUser = await _getUserByContact(contact);

      if (existingEmailUser != null) {
        final data = existingEmailUser.data();
        final bool verified = data['verified'] == true;
        final bool passwordSet = data['passwordSet'] == true;

        if (verified && passwordSet) {
          _showSnackBar("This email is already registered.", Colors.red);
          return;
        }
      }

      if (existingContactUser != null) {
        final data = existingContactUser.data();
        final bool verified = data['verified'] == true;
        final bool passwordSet = data['passwordSet'] == true;

        if (verified && passwordSet) {
          _showSnackBar("This contact number is already registered.", Colors.red);
          return;
        }

        if (existingEmailUser == null ||
            existingContactUser.id != existingEmailUser.id) {
          _showSnackBar("This contact number is already registered.", Colors.red);
          return;
        }
      }

      final code = (100000 + Random().nextInt(900000)).toString();

      final response = await http
          .post(
            Uri.parse(_verificationUrl),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "email": email,
              "code": code,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode != 200) {
        _showSnackBar(
          "Failed to send verification email (${response.statusCode}).",
          Colors.red,
        );
        return;
      }

      final userData = {
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
        'passwordSet': false,
        'approved': false,
        'status': 'Unavailable',
        'smsOptIn': false,
        'createdAt': existingEmailUser == null
            ? FieldValue.serverTimestamp()
            : existingEmailUser.data()['createdAt'] ?? FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (existingEmailUser != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(existingEmailUser.id)
            .update(userData);
      } else {
        await FirebaseFirestore.instance.collection('users').add(userData);
      }

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) {
          Future.delayed(const Duration(seconds: 2), () {
            if (!mounted) return;

            if (Navigator.of(dialogCtx).canPop()) {
              Navigator.of(dialogCtx).pop();
            }

            Navigator.of(context).pushReplacementNamed(
              '/verification',
              arguments: email, // fixed: String only
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
    } on TimeoutException {
      _showSnackBar(
        "Request timeout: could not reach verification server.",
        Colors.red,
      );
    } on SocketException catch (e) {
      _showSnackBar("Network error: ${e.message}", Colors.red);
    } catch (e) {
      _showSnackBar("Something went wrong: $e", Colors.red);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  InputDecoration _input(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      enabled: !_isSubmitting,
    );
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
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                  ),
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
                enabled: !_isSubmitting,
                textInputAction: TextInputAction.next,
                decoration: _input("Full Name"),
              ),
              const SizedBox(height: 20),

              TextField(
                controller: _emailController,
                enabled: !_isSubmitting,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: _input("Email"),
              ),
              const SizedBox(height: 20),

              TextField(
                controller: _contactController,
                enabled: !_isSubmitting,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: _input("Contact Number"),
              ),
              const SizedBox(height: 20),

              TextField(
                controller: _addressController,
                readOnly: true,
                enabled: !_isSubmitting,
                decoration: _input(
                  "Select Address (Tap to Open Map)",
                ).copyWith(
                  suffixIcon: const Icon(Icons.map),
                ),
                onTap: _isSubmitting
                    ? null
                    : () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const MapPickerScreen(apiKey: _googleApiKey),
                          ),
                        );

                        if (!mounted) return;

                        if (result != null && result is Map<String, dynamic>) {
                          setState(() {
                            _addressController.text =
                                (result["address"] ?? "").toString();
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
                  onPressed: _isSubmitting ? null : _register,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFA30000),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFA30000),
                    disabledForegroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text(
                          "Register",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
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
}