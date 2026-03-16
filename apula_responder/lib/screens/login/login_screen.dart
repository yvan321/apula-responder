import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

// YOUR SCREENS
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

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
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

  Future<void> _saveSession({
    required String uid,
    required String email,
    required Map<String, dynamic> userData,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool('isLoggedIn', true);
    await prefs.setString('uid', uid);
    await prefs.setString('email', email);
    await prefs.setString('role', (userData['role'] ?? '').toString());
    await prefs.setString('name', (userData['name'] ?? '').toString());
    await prefs.setBool('approved', userData['approved'] == true);
    await prefs.setBool('verified', userData['verified'] == true);
    await prefs.setString('status', (userData['status'] ?? '').toString());
  }

  Future<void> _login() async {
    if (_isLoading) return;

    final email = usernameController.text.trim().toLowerCase();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showSnackBar("Please enter both email and password.", Colors.red);
      return;
    }

    if (email.contains("admin")) {
      _showSnackBar(
        "Admin accounts must log in via the web dashboard.",
        Colors.red,
      );
      return;
    }

    setState(() => _isLoading = true);

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

      final userDoc = userQuery.docs.first;
      final userData = userDoc.data();

      if (userData['role'] != 'responder') {
        _showSnackBar(
          "Only responder accounts can log in on this app.",
          Colors.red,
        );
        await FirebaseAuth.instance.signOut();
        return;
      }

      if (userData['verified'] != true) {
        _showSnackBar("Please verify your email first.", Colors.red);
        await FirebaseAuth.instance.signOut();
        return;
      }

      if (userData['approved'] != true) {
        _showSnackBar(
          "Your account is waiting for admin approval.",
          Colors.orange,
        );
        await FirebaseAuth.instance.signOut();
        return;
      }

      if ((userData['status'] ?? '').toString().toLowerCase() == "declined") {
        _showSnackBar("Your account was declined by the admin.", Colors.red);
        await FirebaseAuth.instance.signOut();
        return;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userDoc.id)
          .update({
        'uid': user.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await FCMService.saveFcmToken(user.uid, email);

      await _saveSession(
        uid: user.uid,
        email: email,
        userData: userData,
      );

      _showSnackBar("Login successful!", Colors.green);

      if (!mounted) return;

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
      } else if (e.code == 'invalid-email') {
        _showSnackBar("Invalid email format.", Colors.red);
      } else {
        _showSnackBar("Firebase error: ${e.message}", Colors.red);
      }
    } catch (e) {
      _showSnackBar("Something went wrong: $e", Colors.red);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
                    TextField(
                      controller: usernameController,
                      enabled: !_isLoading,
                      style: TextStyle(color: colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: "Email",
                        labelStyle: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.8),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: passwordController,
                      enabled: !_isLoading,
                      obscureText: _obscurePassword,
                      style: TextStyle(color: colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: "Password",
                        labelStyle: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.8),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        suffixIcon: IconButton(
                          onPressed: _isLoading
                              ? null
                              : () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFA30000),
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _isLoading ? null : _login,
                      child: _isLoading
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
                              "Login",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                    ),
                    const SizedBox(height: 20),
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
                          onTap: _isLoading
                              ? null
                              : () {
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