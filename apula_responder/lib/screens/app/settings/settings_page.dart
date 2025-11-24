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
  bool _darkMode = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadResponderData();
  }

  // 🔥 Load Firestore user data by email (works with random doc ID)
  Future<void> _loadResponderData() async {
    final user = FirebaseAuth.instance.currentUser;

    final query = await FirebaseFirestore.instance
        .collection("users")
        .where("email", isEqualTo: user!.email)
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


  Future<void> _logout() async {
  try {
    await FirebaseAuth.instance.signOut();

    if (!mounted) return;

    Navigator.of(context).pushNamedAndRemoveUntil(
      '/login', // make sure your login route is named '/login'
      (route) => false,
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Logout failed: $e")),
    );
  }
}


  @override
  Widget build(BuildContext context) {
    const redColor = Color(0xFFA30000);
    const titleColor = Colors.white;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [redColor, Colors.black],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 20, top: 20),
                child: Text(
                  "Responder Settings",
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 50),

              Expanded(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: double.infinity,
                        height: double.infinity,   // 🔥 ADD THIS
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(25),
                          topRight: Radius.circular(25),
                        ),
                        border: const Border(
                          top: BorderSide(color: redColor, width: 3),
                        ),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          vertical: 30,  // 🔥 Reduced vertical padding since profile is removed
                          horizontal: 20,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // 👨‍🚒 Responder Info
                            Column(
                              children: [
                                Text(
                                  _loading ? "Loading..." : responderName,
                                  style: const TextStyle(
                                    color: redColor,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),

                                Text(
                                  _loading ? "Loading..." : responderAddress,
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 35),

                            _buildThemeToggleTile(),
                            _buildSettingsTile(
                              Icons.notifications_none_outlined,
                              "Notification Preferences",
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const NotifSettingsPage(),
                                  ),
                                );
                              },
                            ),
                            _buildSettingsTile(
                              Icons.account_circle_outlined,
                              "Account Settings",
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const AccountSettingsPage(),
                                  ),
                                );
                              },
                            ),
                            _buildSettingsTile(
                              Icons.info_outline,
                              "About the System",
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const AboutPage(),
                                  ),
                                );
                              },
                            ),
                            _buildSettingsTile(
  Icons.logout,
  "Log Out",
  onTap: () {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm Logout"),
        content: const Text("Are you sure you want to log out?"),
        actions: [
          TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text("Logout"),
            onPressed: () {
              Navigator.pop(context); // close dialog
              _logout(); // call your function
            },
          ),
        ],
      ),
    );
  },
),
                          ],
                        ),
                      ),
                    ),

                    // ❌ Entire profile picture + edit icon REMOVED
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Widget _buildSettingsTile(IconData icon, String title,
      {VoidCallback? onTap}) {
    const redColor = Color(0xFFA30000);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ListTile(
        leading: Icon(icon, color: redColor, size: 26),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        trailing: const Icon(Icons.arrow_forward_ios,
            size: 16, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }

  Widget _buildThemeToggleTile() {
    const redColor = Color(0xFFA30000);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Color(0xFFE0E0E0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ListTile(
        leading: Icon(
          _darkMode ? Icons.dark_mode : Icons.light_mode,
          color: redColor,
          size: 26,
        ),
        title: Text(
          _darkMode ? "Dark Mode" : "Light Mode",
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        trailing: Switch(
          value: _darkMode,
          activeColor: redColor,
          onChanged: (value) {
            setState(() => _darkMode = value);
          },
        ),
      ),
    );
  }
}
