import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class SetPasswordScreen extends StatefulWidget {
  final String email;

  const SetPasswordScreen({
    super.key,
    required this.email,
  });

  @override
  State<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends State<SetPasswordScreen> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _isSaving = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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

  Future<void> _showSuccessFlow() async {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (loadingCtx) {
        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;

          if (Navigator.of(loadingCtx).canPop()) {
            Navigator.of(loadingCtx).pop();
          }

          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (successCtx) {
              Future.delayed(const Duration(seconds: 3), () {
                if (!mounted) return;

                if (Navigator.of(successCtx).canPop()) {
                  Navigator.of(successCtx).pop();
                }

                Navigator.pushReplacementNamed(context, '/login');
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
                      "Account Created Successfully!",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFA30000),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "Your registration is pending admin approval. Please wait for an administrator to approve your account before you can log in.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              );
            },
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
                  'assets/fireloading.json',
                  repeat: true,
                ),
              ),
              const SizedBox(height: 20),
              const Center(
                child: Text(
                  "Setting up your account...",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFA30000),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _savePassword() async {
    if (_isSaving) return;

    FocusScope.of(context).unfocus();

    final email = widget.email.trim().toLowerCase();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (password.isEmpty || confirmPassword.isEmpty) {
      _showSnackBar("Please fill in all fields.", Colors.red);
      return;
    }

    if (password.length < 6) {
      _showSnackBar("Password must be at least 6 characters.", Colors.red);
      return;
    }

    if (password != confirmPassword) {
      _showSnackBar("Passwords do not match.", Colors.red);
      return;
    }

    setState(() => _isSaving = true);

    try {
      final userDoc = await _getUserByEmail(email);

      if (userDoc == null) {
        _showSnackBar(
          "Registration record not found. Please register again.",
          Colors.red,
        );
        return;
      }

      final data = userDoc.data();
      final bool verified = data['verified'] == true;
      final bool passwordSet = data['passwordSet'] == true;

      if (!verified) {
        _showSnackBar("Please verify your OTP first.", Colors.red);
        return;
      }

      if (passwordSet) {
        _showSnackBar(
          "Password is already set for this account. Please log in.",
          Colors.red,
        );
        return;
      }

      try {
        final credential =
            await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );

        final uid = credential.user?.uid;

        await FirebaseFirestore.instance
            .collection('users')
            .doc(userDoc.id)
            .update({
          'uid': uid,
          'verified': true,
          'passwordSet': true,
          'approved': false,
          'authProvider': 'password',
          'verificationCode': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        await FirebaseAuth.instance.signOut();
        await _showSuccessFlow();
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          // This means the auth account already exists from a previous attempt.
          // We cannot safely recover the UID here without signing in, so we
          // mark the Firestore record as passwordSet and tell the user to log in
          // or reset password if needed.

          await FirebaseFirestore.instance
              .collection('users')
              .doc(userDoc.id)
              .update({
            'passwordSet': true,
            'approved': false,
            'authProvider': 'password',
            'verificationCode': FieldValue.delete(),
            'updatedAt': FieldValue.serverTimestamp(),
          });

          _showSnackBar(
            "This account was already created before. Please go to login. If the password is unknown, use Forgot Password.",
            Colors.orange,
          );

          if (!mounted) return;

          Future.delayed(const Duration(seconds: 2), () {
            if (!mounted) return;
            Navigator.pushReplacementNamed(context, '/login');
          });

          return;
        } else if (e.code == 'weak-password') {
          _showSnackBar("Password is too weak.", Colors.red);
          return;
        } else if (e.code == 'invalid-email') {
          _showSnackBar("Invalid email address.", Colors.red);
          return;
        } else {
          _showSnackBar("Firebase Error: ${e.message}", Colors.red);
          return;
        }
      }
    } catch (e) {
      _showSnackBar("Something went wrong: $e", Colors.red);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  InputDecoration _inputDecoration({
    required String label,
    required bool obscureText,
    required VoidCallback onToggle,
  }) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      enabled: !_isSaving,
      suffixIcon: IconButton(
        onPressed: _isSaving ? null : onToggle,
        icon: Icon(
          obscureText ? Icons.visibility_off : Icons.visibility,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 10, top: 10),
              child: InkWell(
                onTap: _isSaving ? null : () => Navigator.pop(context),
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
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 60),
                      child: Text(
                        "Set your password",
                        style: TextStyle(
                          color: Color(0xFFA30000),
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    TextField(
                      controller: _passwordController,
                      enabled: !_isSaving,
                      obscureText: _obscurePassword,
                      decoration: _inputDecoration(
                        label: "New Password",
                        obscureText: _obscurePassword,
                        onToggle: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _confirmPasswordController,
                      enabled: !_isSaving,
                      obscureText: _obscureConfirmPassword,
                      decoration: _inputDecoration(
                        label: "Confirm New Password",
                        obscureText: _obscureConfirmPassword,
                        onToggle: () {
                          setState(() {
                            _obscureConfirmPassword =
                                !_obscureConfirmPassword;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "Password must be at least 6 characters.",
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey,
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFA30000),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFFA30000),
                          disabledForegroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: _isSaving ? null : _savePassword,
                        child: _isSaving
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
                                "Save Password",
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
          ],
        ),
      ),
    );
  }
}