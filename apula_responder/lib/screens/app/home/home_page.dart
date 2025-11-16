import 'dart:async';
import 'package:apula_responder/screens/app/dispatch/dispatch_page.dart';
import 'package:apula_responder/screens/app/notifications/notification_page.dart';
import 'package:apula_responder/screens/app/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:apula_responder/widgets/custom_bottom_nav.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  // 🔥 Firestore Dispatch Tracking
  String _dispatchStatus = "Loading...";
  String _dispatchLocation = "";
  StreamSubscription? _dispatchSub;

  // 🔍 Alert Modal State
  bool _showAlertModal = false;
  Map<String, dynamic>? _alertData;

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
    _listenToDispatchStatus();
  }

  // 🔄 Real-time listener for dispatch status
  void _listenToDispatchStatus() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final dispatchRef = FirebaseFirestore.instance
        .collection('dispatches')
        .where('responderEmail', isEqualTo: user.email?.toLowerCase())
        .orderBy('timestamp', descending: true)
        .limit(1);

    _dispatchSub = dispatchRef.snapshots().listen((snapshot) {
      if (snapshot.docs.isEmpty) {
        setState(() {
          _dispatchStatus = "No Active Dispatch 🔒";
          _dispatchLocation = "";
        });
      } else {
        final data = snapshot.docs.first.data();
        setState(() {
          _dispatchStatus = data['status'] ?? 'Unknown';
          _dispatchLocation = data['alertLocation'] ?? '';
        });
      }
    });
  }

  // 🔍 View alert details modal
  void _openAlertDetails() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final query = await FirebaseFirestore.instance
        .collection('dispatches')
        .where('responderEmail', isEqualTo: user.email?.toLowerCase())
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();

    if (query.docs.isEmpty) return;

    final dispatch = query.docs.first.data();
    final alertId = dispatch["alertId"];

    if (alertId == null) return;

    // Fetch ALERT details
    final alertSnap =
        await FirebaseFirestore.instance.collection("alerts").doc(alertId).get();

    if (!alertSnap.exists) return;

    setState(() {
      _alertData = alertSnap.data();
      _showAlertModal = true;
    });
  }

  // ✅ Mark Dispatch as Resolved (also updates alert)
  void _markAsResolved() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final query = await FirebaseFirestore.instance
        .collection('dispatches')
        .where('responderEmail', isEqualTo: user.email?.toLowerCase())
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      final dispatchDoc = query.docs.first;
      final dispatchId = dispatchDoc.id;
      final data = dispatchDoc.data();
      final alertId = data['alertId'];

      try {
        // 1️⃣ Update dispatch
        await FirebaseFirestore.instance
            .collection('dispatches')
            .doc(dispatchId)
            .update({'status': 'Resolved'});

        // 2️⃣ Also update the alert
        if (alertId != null && alertId.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('alerts')
              .doc(alertId)
              .update({'status': 'Resolved'});
        }

        setState(() {
          _dispatchStatus = "Resolved";
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Dispatch marked as resolved.")),
        );
      } catch (e) {
        debugPrint("❌ Error updating: $e");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to update status.")),
        );
      }
    }
  }

  // 🕒 Time + Date
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
      "December"
    ];
    return months[month - 1];
  }

  @override
  void dispose() {
    _timer?.cancel();
    _dispatchSub?.cancel();
    super.dispose();
  }

  void _onItemTapped(int index) => setState(() => _selectedIndex = index);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Show Alert Modal
    if (_showAlertModal) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog(
          context: context,
          builder: (context) => _alertDetailsModal(),
        );
        _showAlertModal = false;
      });
    }

    return Scaffold(
      appBar: _selectedIndex == 0
          ? AppBar(
              automaticallyImplyLeading: false,
              backgroundColor: theme.appBarTheme.backgroundColor,
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
          const NotificationsPage(),
          const SettingsPage(),
        ],
      ),
      bottomNavigationBar: CustomBottomNavBar(
        selectedIndex: _selectedIndex,
        onItemTapped: _onItemTapped,
        backgroundColor: theme.colorScheme.surface,
        activeColor: const Color(0xFFA30000),
        inactiveColor: Colors.grey,
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
          const Text("Ready to Respond",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          // DISPATCH STATUS CARD
          _buildDispatchStatusCard(),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(child: _buildTimeCard()),
              const SizedBox(width: 12),
              Expanded(child: _buildLocationCard()),
            ],
          ),

          const SizedBox(height: 20),

          // RECENT INCIDENTS
          const Text("Recent Fire Incidents",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _incidentCard("Molino 3 - Fire Alert", "2 mins ago", "On the way"),
          _incidentCard("Niog - Smoke Detected", "10 mins ago", "Resolved"),

          const SizedBox(height: 20),

          // ANNOUNCEMENTS
          const Text("Announcements",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _reportItem("Fire Drill Schedule - Nov 5", "Yesterday"),
          _reportItem("Equipment Maintenance Notice", "2 days ago"),

          const SizedBox(height: 30),
        ],
      ),
    );
  }

  // ====================== DISPATCH STATUS CARD ======================
  Widget _buildDispatchStatusCard() {
    Color startColor, endColor;
    IconData icon;

    if (_dispatchStatus == "Dispatched") {
      startColor = Colors.red;
      endColor = Colors.orange;
      icon = Icons.local_fire_department;
    } else if (_dispatchStatus == "Resolved") {
      startColor = Colors.green;
      endColor = Colors.teal;
      icon = Icons.check_circle;
    } else {
      startColor = Colors.grey;
      endColor = Colors.blueGrey;
      icon = Icons.lock_outline;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [startColor, endColor]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: startColor.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_dispatchStatus,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                if (_dispatchLocation.isNotEmpty)
                  Text("Location: $_dispatchLocation",
                      style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),

          if (_dispatchStatus == "Dispatched") ...[
            ElevatedButton(
              onPressed: _openAlertDetails,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.blue,
              ),
              child: const Text("View"),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _markAsResolved,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.red,
              ),
              child: const Text("Resolve"),
            ),
          ],
        ],
      ),
    );
  }

  // ====================== ALERT DETAILS MODAL ======================
  Widget _alertDetailsModal() {
    if (_alertData == null) return const SizedBox();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        width: 350,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("🔥 Alert Details",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),

              Text("Type: ${_alertData!['type'] ?? 'Unknown'}"),
              Text("Location: ${_alertData!['location'] ?? 'Unknown'}"),
              Text("Status: ${_alertData!['status'] ?? 'Unknown'}"),
              const SizedBox(height: 12),

              const Text("👤 Reporter:",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text("Name: ${_alertData!['userName'] ?? 'N/A'}"),
              Text("Contact: ${_alertData!['userContact'] ?? 'N/A'}"),
              Text("Address: ${_alertData!['userAddress'] ?? 'N/A'}"),
              const SizedBox(height: 12),

              const Text("🕒 Date & Time:",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text(_alertData!['timestamp'] != null
                  ? DateTime.fromMillisecondsSinceEpoch(
                          _alertData!['timestamp'].seconds * 1000)
                      .toString()
                  : "N/A"),
              const SizedBox(height: 12),

              const Text("📝 Description:",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text(_alertData!['description'] ?? "No description provided"),
              const SizedBox(height: 20),

              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Close"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ====================== OTHER WIDGETS ======================
  Widget _buildTimeCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: _isDay
                  ? [Colors.yellow.shade200, Colors.orange.shade300]
                  : [Colors.indigo.shade700, Colors.indigo.shade900]),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_isDay ? Icons.wb_sunny : Icons.nightlight_round,
                color: _isDay ? Colors.black : Colors.white, size: 28),
            const SizedBox(height: 8),
            Text(_time,
                style: TextStyle(
                    color: _isDay ? Colors.black : Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
            Text(_date,
                style: TextStyle(
                    color: (_isDay ? Colors.black : Colors.white)
                        .withOpacity(0.7))),
          ],
        ),
      );

  Widget _buildLocationCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Colors.teal, Colors.tealAccent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.location_on, color: Colors.white, size: 28),
            SizedBox(height: 8),
            Text("Main BFP",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
            Text("Bacoor City",
                style: TextStyle(color: Colors.white70, fontSize: 14)),
          ],
        ),
      );

  Widget _incidentCard(String title, String time, String status) => Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          leading: const Icon(Icons.local_fire_department, color: Colors.red),
          title: Text(title),
          subtitle: Text(time),
          trailing: Text(status,
              style: TextStyle(
                  color: status == "Resolved" ? Colors.green : Colors.orange,
                  fontWeight: FontWeight.bold)),
        ),
      );

  Widget _reportItem(String title, String time) => Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          leading: const Icon(Icons.announcement, color: Colors.blue),
          title: Text(title),
          subtitle: Text(time),
        ),
      );
}
