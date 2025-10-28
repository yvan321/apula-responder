import 'dart:async';
import 'package:apula_responder/screens/app/dispatch/dispatch_page.dart';
import 'package:flutter/material.dart';
import 'package:apula_responder/widgets/custom_bottom_nav.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  String _time = "", _date = "";
  Timer? _timer;
  bool _isDay = true;

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
  }

  void _updateTime() {
    final now = DateTime.now();
    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final period = now.hour >= 12 ? "PM" : "AM";

    setState(() {
      _time =
          "$hour:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')} $period";
      _date = "${_monthName(now.month)} ${now.day}, ${now.year}";
      _isDay = now.hour >= 6 && now.hour < 18;
    });
  }

  String _monthName(int month) {
    const months = [
      "January",
      "February",
      "March",
      "April",
      "May",
      "June",
      "July",
      "August",
      "September",
      "October",
      "November",
      "December",
    ];
    return months[month - 1];
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _onItemTapped(int index) => setState(() => _selectedIndex = index);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ✅ Only show AppBar if user is on Home
      appBar: _selectedIndex == 0
          ? AppBar(
              automaticallyImplyLeading: false,
              backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
              elevation: 0,
              title: Row(
                children: [
                  Image.asset("assets/logo.png", height: 40),
                  const SizedBox(width: 8),
                ],
              ),
            )
          : null,

      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildDashboard(context),
          const DispatchPage(devices: []),
          const Center(child: Text("Notifications 🔔")),
          const Center(child: Text("Settings ⚙️")),
        ],
      ),

      bottomNavigationBar: CustomBottomNavBar(
        selectedIndex: _selectedIndex,
        onItemTapped: _onItemTapped,
      ),
    );
  }

  // ====================== HOME / DASHBOARD ======================
  Widget _buildDashboard(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Ready to Respond",
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          // 🔥 Status Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Colors.red, Colors.orange],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: const [
                Icon(
                  Icons.local_fire_department,
                  color: Colors.white,
                  size: 40,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "No Active Dispatch 🔒",
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 🕒 Time & Location
          Row(
            children: [
              Expanded(child: _buildTimeCard()),
              const SizedBox(width: 12),
              Expanded(child: _buildLocationCard()),
            ],
          ),
          const SizedBox(height: 20),

          const Text(
            "Recent Fire Incidents",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          _incidentCard("Molino 3 - Fire Alert", "2 mins ago", "On the way"),
          _incidentCard("Niog - Smoke Detected", "10 mins ago", "Resolved"),
          const SizedBox(height: 20),

          // 📜 Announcements
          const Text(
            "Announcements",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          _reportItem("Fire Drill Schedule - Nov 5", "Yesterday"),
          _reportItem("Equipment Maintenance Notice", "2 days ago"),
        ],
      ),
    );
  }

  // ====================== REUSABLE WIDGETS ======================
  Widget _buildTimeCard() {
    final gradientColors = _isDay
        ? [Colors.yellow.shade200, Colors.orange.shade300]
        : [Colors.indigo.shade700, Colors.indigo.shade900];
    final textColor = _isDay ? Colors.black : Colors.white;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradientColors),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 6,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _isDay ? Icons.wb_sunny : Icons.nightlight_round,
            color: textColor,
            size: 28,
          ),
          const SizedBox(height: 8),
          Text(
            _time,
            style: TextStyle(
              color: textColor,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(_date, style: TextStyle(color: textColor.withOpacity(0.7))),
        ],
      ),
    );
  }

  Widget _buildLocationCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.teal, Colors.tealAccent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.teal.withOpacity(0.3),
            blurRadius: 6,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.location_on, color: Colors.white, size: 28),
          SizedBox(height: 8),
          Text(
            "Main BFP",
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            "Bacoor City",
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _incidentCard(String title, String time, String status) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: const Icon(Icons.local_fire_department, color: Colors.red),
        title: Text(title),
        subtitle: Text(time),
        trailing: Text(
          status,
          style: TextStyle(
            color: status == "Resolved" ? Colors.green : Colors.orange,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _reportItem(String title, String time) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: const Icon(Icons.announcement, color: Colors.blue),
        title: Text(title),
        subtitle: Text(time),
      ),
    );
  }
}
