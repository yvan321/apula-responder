// lib/screens/app/settings/settings_page.dart

import 'package:apula_responder/screens/app/settings/account_settings.dart';
import 'package:apula_responder/screens/app/settings/notifsetting_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'about_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String responderName = "";
  String responderAddress = "";
  bool _loading = true;

  final Color redColor = const Color(0xFFA30000);

  @override
  void initState() {
    super.initState();
    _loadResponderData();
  }

  // 🔥 Load Firestore user data
  Future<void> _loadResponderData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final query = await FirebaseFirestore.instance
        .collection("users")
        .where("email", isEqualTo: user.email)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      final doc = query.docs.first;
      setState(() {
        responderName = doc["name"] ?? "";
        responderAddress = doc["address"] ?? "";
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  // 🔥 Logout method
  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;

      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Logout failed: $e")),
      );
    }
  }

  // 🔥 Styled Logout Dialog
  void _showLogoutDialog() {
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.logout, size: 50, color: redColor),
              const SizedBox(height: 16),

              Text(
                "Confirm Logout",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),

              const SizedBox(height: 10),
              Text(
                "Are you sure you want to log out?",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                ),
              ),

              const SizedBox(height: 25),

              Row(
                children: [
                  // Cancel Button
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.onSurface,
                        side: BorderSide(color: theme.colorScheme.outline),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Cancel"),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Logout Button
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: redColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        _logout();
                      },
                      child: const Text("Logout"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // UI TILE BUILDER
  Widget _settingsTile(IconData icon, String title, {VoidCallback? onTap}) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        leading: Icon(icon, color: redColor, size: 26),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 16,
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
        trailing: Icon(Icons.arrow_forward_ios,
            size: 16, color: theme.colorScheme.onSurface.withOpacity(0.5)),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // HEADER TITLE
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Text(
                "Responder Settings",
                style: TextStyle(
                  color: redColor,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            // WHITE / DARK SURFACE CONTAINER
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(22),
                    topRight: Radius.circular(22),
                  ),
                  border: Border(
                    top: BorderSide(
                      color: redColor,
                      width: 3,
                    ),
                  ),
                ),
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // ⬇️⬇️⬇️ ADDED LOGO HERE ⬇️⬇️⬇️

                      Image.asset(
                        "assets/logo.png",
                        height: 180,
                        width: 180,
                      ),
                      const SizedBox(height: 12),

                      Text(
                        _loading ? "Loading..." : responderName,
                        style: TextStyle(
                          color: redColor,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 4),

                      Text(
                        _loading ? "Loading..." : responderAddress,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withOpacity(0.7),
                          fontSize: 14,
                        ),
                      ),

                      // ⬆️⬆️⬆️ END OF LOGO SECTION ⬆️⬆️⬆️

                      const SizedBox(height: 35),

                      // SETTINGS TILES
                      _settingsTile(
                        Icons.notifications_none_outlined,
                        "Notification Preferences",
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const NotifSettingsPage(),
                          ),
                        ),
                      ),
                      _settingsTile(
                        Icons.account_circle_outlined,
                        "Account Settings",
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AccountSettingsPage(),
                          ),
                        ),
                      ),
                      _settingsTile(
                        Icons.info_outline,
                        "About the System",
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AboutPage(),
                          ),
                        ),
                      ),
                      _settingsTile(
                        Icons.logout,
                        "Log Out",
                        onTap: _showLogoutDialog,
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
}
