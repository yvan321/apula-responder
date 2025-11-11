import 'package:apula_responder/screens/app/settings/account_settings.dart';
import 'package:apula_responder/screens/app/settings/notifsetting_page.dart';
import 'package:flutter/material.dart';
import 'about_page.dart'; // ✅ Ensure correct path

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // Mock responder info
  final String _responderName = "Responder Alpha Team 2";
  final String _responderStation = "Molino Fire Station";
  final String _responderID = "ID: 0421-BFP";

  bool _darkMode = false; // local toggle only, not app-wide

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
              // 🏷️ Title
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

              // ⚪ Inner Container
              Expanded(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: double.infinity,
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
                          vertical: 70,
                          horizontal: 20,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // 👨‍🚒 Responder Info
                            Column(
                              children: [
                                Text(
                                  _responderName,
                                  style: const TextStyle(
                                    color: redColor,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _responderStation,
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _responderID,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 35),

                            // ⚙️ Settings List
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
                              onTap: () =>
                                  _showSnack("Logged out successfully."),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 👤 Profile Picture
                    Positioned(
                      top: -55,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            const CircleAvatar(
                              radius: 55,
                              backgroundImage: AssetImage(
                                'assets/examples/responder_pic.jpg',
                              ),
                              backgroundColor: Colors.transparent,
                            ),
                            Positioned(
                              bottom: 6,
                              right: 6,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 3,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.edit,
                                  size: 18,
                                  color: redColor,
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
            ],
          ),
        ),
      ),
    );
  }

  // 🔔 Snackbar helper
  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  // ⚙️ Settings Tile
  Widget _buildSettingsTile(
    IconData icon,
    String title, {
    VoidCallback? onTap,
  }) {
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
        trailing: const Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: Colors.grey,
        ),
        onTap: onTap ?? () {},
      ),
    );
  }

  // 🌗 Local Theme Toggle (non-global)
  Widget _buildThemeToggleTile() {
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
