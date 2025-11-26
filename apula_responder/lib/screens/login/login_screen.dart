import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// YOUR SCREENS
import '../main_screen.dart';
import '../app/home/home_page.dart';

// FCM service for saving notification tokens
import '../../services/fcm_services.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final LocalAuthentication auth = LocalAuthentication();

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

  // ============================================================
  // 🔥 LOGIN FUNCTION + SAVE FCM TOKEN
  // ============================================================
  Future<void> _login() async {
    final email = usernameController.text.trim().toLowerCase();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showSnackBar("Please enter both email and password.", Colors.red);
      return;
    }

    if (email.contains("admin")) {
      _showSnackBar("Admin accounts must log in via the web dashboard.", Colors.red);
      return;
    }

    try {
      final userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);

      final user = userCredential.user!;

      final userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (userQuery.docs.isEmpty) {
        _showSnackBar("No user record found in Firestore.", Colors.red);
        await FirebaseAuth.instance.signOut();
        return;
      }

      final userData = userQuery.docs.first.data();

      if (userData['role'] != 'responder') {
        _showSnackBar("Only responder accounts can log in on this app.", Colors.red);
        await FirebaseAuth.instance.signOut();
        return;
      }

      if (userData['verified'] != true) {
        _showSnackBar("Please verify your account before logging in.", Colors.red);
        await FirebaseAuth.instance.signOut();
        return;
      }

      // 🔥 Save FCM token
      await FCMService.saveFcmToken(user.uid, email);

      // SUCCESS
      _showSnackBar("Login successful!", Colors.green);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomePage()),
      );

    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        _showSnackBar("No account found with this email.", Colors.red);
      } else if (e.code == 'wrong-password') {
        _showSnackBar("Incorrect password.", Colors.red);
      } else if (e.code == 'invalid-credential') {
        _showSnackBar("Invalid email or password.", Colors.red);
      } else {
        _showSnackBar("Firebase error: ${e.message}", Colors.red);
      }
    } catch (e) {
      _showSnackBar("Something went wrong: $e", Colors.red);
    }
  }

  // ============================================================
  // FINGERPRINT LOGIN
  // ============================================================
  Future<void> _authenticate() async {
    bool authenticated = false;
    try {
      authenticated = await auth.authenticate(
        localizedReason: 'Use your fingerprint to log in',
        options: const AuthenticationOptions(biometricOnly: true),
      );
    } catch (e) {
      _showSnackBar("Error: $e", Colors.red);
      return;
    }

    if (authenticated) {
      _showSnackBar("Fingerprint login successful", Colors.green);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MainScreen()),
      );
    } else {
      _showSnackBar("Fingerprint login failed", Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black, Color(0xFFA30000)],
          ),
        ),

        child: Stack(
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 100),
                child: Image.asset(
                  "assets/logo.png",
                  width: 150,
                ),
              ),
            ),

            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: MediaQuery.of(context).size.height * 0.55,
                width: double.infinity,
                padding: const EdgeInsets.all(20),

                // FIX: Use theme surface for dark/light mode
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(30),
                    topRight: Radius.circular(30),
                  ),
                ),

                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "Log In",
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFA30000),
                      ),
                    ),

                    const SizedBox(height: 30),

                    // EMAIL
                    TextField(
                      controller: usernameController,
                      style: TextStyle(color: colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: "Email",
                        labelStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.8)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // PASSWORD
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      style: TextStyle(color: colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: "Password",
                        labelStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.8)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),

                    const SizedBox(height: 30),

                    // LOGIN BUTTON
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFA30000),
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _login,
                      child: const Text(
                        "Login",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // FINGERPRINT
                    TextButton(
                      onPressed: () {
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (context) {
                            final textTheme = Theme.of(context).textTheme;

                            return Dialog(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              backgroundColor: colorScheme.surface,

                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.fingerprint,
                                      size: 80,
                                      color: Color(0xFFA30000),
                                    ),
                                    const SizedBox(height: 15),

                                    Text(
                                      "Fingerprint Authentication",
                                      style: textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),

                                    const SizedBox(height: 10),

                                    Text(
                                      "Place your finger on the sensor to continue",
                                      style: textTheme.bodyMedium?.copyWith(
                                        color: colorScheme.onSurface.withOpacity(0.7),
                                      ),
                                      textAlign: TextAlign.center,
                                    ),

                                    const SizedBox(height: 20),

                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFA30000),
                                        minimumSize: const Size(double.infinity, 45),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                      ),
                                      onPressed: () {
                                        Navigator.pop(context);
                                        _authenticate();
                                      },
                                      child: const Text(
                                        "Authenticate",
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 10),

                                    TextButton(
                                      onPressed: () {
                                        Navigator.pop(context);
                                      },
                                      child: Text(
                                        "Cancel",
                                        style: TextStyle(
                                          color: colorScheme.onSurface.withOpacity(0.6),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                      child: const Text(
                        "Use Fingerprint",
                        style: TextStyle(color: Color(0xFFA30000)),
                      ),
                    ),

                    const SizedBox(height: 10),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Don’t have an account? ",
                          style: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.7),
                            fontSize: 14,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.pushNamed(context, '/register');
                          },
                          child: const Text(
                            "Sign up",
                            style: TextStyle(
                              color: Color(0xFFA30000),
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
