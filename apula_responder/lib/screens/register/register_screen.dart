import 'dart:math';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:apula_responder/screens/register/map_picker.dart';


class RegisterScreen extends StatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  double? selectedLat;
  double? selectedLng;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _contactController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message, Color bgColor) {
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

    try {
      final code = (100000 + Random().nextInt(900000)).toString();

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
        'verified': false,           // email not verified yet
        'approved': false,           // waiting for admin approval
        'status': "Unavailable",     // responder cannot be dispatched yet
        'createdAt': FieldValue.serverTimestamp(),
      });

      final url = Uri.parse("http://10.238.220.202:3005/send-verification");


      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": email, "code": code}),
      );

      if (response.statusCode == 200) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            Future.delayed(const Duration(seconds: 2), () {
              Navigator.pop(context);
              Navigator.pushReplacementNamed(context, '/verification', arguments: email);
            });
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 200,
                    width: 400,
                    child: Lottie.asset('assets/check orange.json', repeat: false),
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
        _showSnackBar("Failed to send verification email.", Colors.red);
      }
    } catch (e) {
      _showSnackBar("Something went wrong: $e", Colors.red);
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
              // Back Button
              InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(30),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(shape: BoxShape.circle),
                  child: Icon(Icons.chevron_left, size: 30, color: Theme.of(context).colorScheme.primary),
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

              // Name
              TextField(
                controller: _nameController,
                decoration: _input("Full Name"),
              ),
              const SizedBox(height: 20),

              // Email
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: _input("Email"),
              ),
              const SizedBox(height: 20),

              // Contact
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
                decoration: _input("Select Station Address (Tap to Open Map)").copyWith(
                  suffixIcon: const Icon(Icons.map),
                ),
                onTap: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MapPickerScreen(),

                    ),
                  );

                  if (result != null && result is Map<String, dynamic>) {
                    setState(() {
                      _addressController.text = result["address"];
                      selectedLat = result["lat"];
                      selectedLng = result["lng"];
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _register,
                  child: const Text(
                    "Register",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
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
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }
}
