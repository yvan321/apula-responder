import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:lottie/lottie.dart';

import '../register/setpassword_screen.dart';

enum SnackBarType { success, error, info }

class VerificationScreen extends StatefulWidget {
  final String email;

  const VerificationScreen({
    super.key,
    required this.email,
  });

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  static const String _verificationUrl =
      "https://apula-web.vercel.app/api/send-verification";

  final List<TextEditingController> _codeControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  Timer? _timer;
  int _secondsRemaining = 120;

  bool _isVerifying = false;
  bool _isResending = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _codeControllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _showSnackBar(String message, SnackBarType type) {
    Color bgColor;
    IconData icon;

    switch (type) {
      case SnackBarType.success:
        bgColor = Colors.green;
        icon = Icons.check_circle;
        break;
      case SnackBarType.error:
        bgColor = Colors.red;
        icon = Icons.error;
        break;
      case SnackBarType.info:
        bgColor = Colors.blue;
        icon = Icons.info;
        break;
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _startTimer() {
    _timer?.cancel();
    _secondsRemaining = 120;

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining <= 0) {
        timer.cancel();
      } else {
        if (mounted) {
          setState(() {
            _secondsRemaining--;
          });
        }
      }
    });

    if (mounted) {
      setState(() {});
    }
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

  void _clearCodeFields() {
    for (final controller in _codeControllers) {
      controller.clear();
    }
    if (_focusNodes.isNotEmpty) {
      FocusScope.of(context).requestFocus(_focusNodes[0]);
    }
  }

  Future<void> _resendCode() async {
    if (_isResending || _secondsRemaining > 0) return;

    setState(() => _isResending = true);

    try {
      final normalizedEmail = widget.email.trim().toLowerCase();
      final newCode = (100000 + Random().nextInt(900000)).toString();

      final userDoc = await _getUserByEmail(normalizedEmail);

      if (userDoc == null) {
        _showSnackBar("Registration record not found.", SnackBarType.error);
        return;
      }

      final userData = userDoc.data();
      final bool alreadyVerified = userData['verified'] == true;

      if (alreadyVerified) {
        _showSnackBar("This account is already verified.", SnackBarType.info);
        return;
      }

      final response = await http.post(
        Uri.parse(_verificationUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "email": normalizedEmail,
          "code": newCode,
        }),
      );

      if (response.statusCode != 200) {
        _showSnackBar("Failed to resend code.", SnackBarType.error);
        return;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userDoc.id)
          .update({
        'verificationCode': newCode,
        'verified': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _clearCodeFields();
      _startTimer();
      _showSnackBar("A new verification code was sent.", SnackBarType.success);
    } catch (e) {
      _showSnackBar("Error resending code: $e", SnackBarType.error);
    } finally {
      if (mounted) {
        setState(() => _isResending = false);
      }
    }
  }

  Future<void> _confirmCode() async {
    if (_isVerifying) return;

    final code = _codeControllers.map((c) => c.text.trim()).join();
    final normalizedEmail = widget.email.trim().toLowerCase();

    if (code.length != 6) {
      _showSnackBar("Please enter the 6-digit code.", SnackBarType.error);
      return;
    }

    setState(() => _isVerifying = true);

    try {
      final userDoc = await _getUserByEmail(normalizedEmail);

      if (userDoc == null) {
        _showSnackBar("Registration record not found.", SnackBarType.error);
        return;
      }

      final data = userDoc.data();
      final storedCode = (data['verificationCode'] ?? "").toString();
      final bool alreadyVerified = data['verified'] == true;

      if (alreadyVerified) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => SetPasswordScreen(email: normalizedEmail),
          ),
        );
        return;
      }

      if (storedCode != code) {
        _showSnackBar("Invalid code. Please try again.", SnackBarType.error);
        return;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userDoc.id)
          .update({
        'verified': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });

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

            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => SetPasswordScreen(
                  email: normalizedEmail,
                ),
              ),
            );
          });

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Lottie.asset(
                  'assets/check orange.json',
                  repeat: false,
                  height: 200,
                ),
                const SizedBox(height: 20),
                const Text(
                  "Verification successful!",
                  style: TextStyle(
                    color: Color(0xFFA30000),
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          );
        },
      );
    } catch (e) {
      _showSnackBar("Error verifying code: $e", SnackBarType.error);
    } finally {
      if (mounted) {
        setState(() => _isVerifying = false);
      }
    }
  }

  Widget _buildCodeField(int index) {
    return SizedBox(
      width: 48,
      child: TextField(
        controller: _codeControllers[index],
        focusNode: _focusNodes[index],
        enabled: !_isVerifying && !_isResending,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
        decoration: InputDecoration(
          counterText: "",
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(
              color: Color(0xFFA30000),
              width: 2,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(
              color: Color(0xFFA30000),
              width: 2,
            ),
          ),
        ),
        onChanged: (value) {
          if (value.length > 1) {
            final singleChar = value.substring(0, 1);
            _codeControllers[index].text = singleChar;
            _codeControllers[index].selection =
                const TextSelection.collapsed(offset: 1);
          }

          if (value.isNotEmpty && index < 5) {
            FocusScope.of(context).requestFocus(_focusNodes[index + 1]);
          } else if (value.isEmpty && index > 0) {
            FocusScope.of(context).requestFocus(_focusNodes[index - 1]);
          }
        },
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
            IconButton(
              icon: Icon(
                Icons.chevron_left,
                size: 40,
                color: Theme.of(context).colorScheme.primary,
              ),
              onPressed: (_isVerifying || _isResending)
                  ? null
                  : () => Navigator.pop(context),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 40),
                      child: Text(
                        "Enter Verification Code",
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    RichText(
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                        children: [
                          const TextSpan(
                            text: "We’ve sent a 6-digit code to ",
                          ),
                          TextSpan(
                            text: widget.email,
                            style: const TextStyle(
                              color: Color(0xFFA30000),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const TextSpan(text: "."),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(6, (index) => _buildCodeField(index)),
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
                        onPressed: _isVerifying ? null : _confirmCode,
                        child: _isVerifying
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
                                "Verify",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: _secondsRemaining > 0
                          ? Text(
                              "Resend available in $_secondsRemaining s",
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 14,
                              ),
                            )
                          : TextButton(
                              onPressed: _isResending ? null : _resendCode,
                              child: _isResending
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          Color(0xFFA30000),
                                        ),
                                      ),
                                    )
                                  : const Text(
                                      "Resend Code",
                                      style: TextStyle(
                                        color: Color(0xFFA30000),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
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