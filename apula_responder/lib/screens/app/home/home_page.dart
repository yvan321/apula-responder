// lib/screens/app/home/home_page.dart
import 'dart:async';
import 'package:apula_responder/screens/app/dispatch/dispatch_page.dart';
import 'package:apula_responder/screens/app/notifications/notification_page.dart';
import 'package:apula_responder/screens/app/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:apula_responder/widgets/custom_bottom_nav.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

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

  // 🔥 Dispatch Tracking
  String _dispatchStatus = "Loading...";
  StreamSubscription? _dispatchSub;
  String _callerAddress = "";

  // 🔥 Recent Alerts
  List<Map<String, dynamic>> _recentAlerts = [];

  // 🔍 Alert Modal
  bool _showAlertModal = false;
  Map<String, dynamic>? _alertData;

  // 🔥 Responder Availability
  String _responderStatus = "Available";

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
    _listenToDispatchStatus();
    _loadRecentAlerts();
    _getResponderStatus();
  }

  // ---------------------------------------------------------------
  // 🔥 Load Responder Status (uses EXACT email)
  // ---------------------------------------------------------------
  Future<void> _getResponderStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      QuerySnapshot snap = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: user.email)
          .limit(1)
          .get();

      if (snap.docs.isNotEmpty) {
        final data = snap.docs.first.data() as Map<String, dynamic>;
        setState(() {
          _responderStatus = data['status'] ?? "Available";
        });
      }
    } catch (e) {
      debugPrint("Status load error: $e");
    }
  }

  // ---------------------------------------------------------------
  // 🔥 Toggle Responder Status
  // ---------------------------------------------------------------
  Future<void> _toggleResponderStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

 String newStatus;

if (_responderStatus == "Available") {
  newStatus = "Unavailable";
} else if (_responderStatus == "Unavailable") {
  newStatus = "Available";
} else if (_responderStatus == "Dispatched") {
  // DO NOT CHANGE STATUS WHEN DISPATCHED
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text("Cannot change status while dispatched.")),
  );
  return;
} else {
  newStatus = "Unavailable";
}


    try {
      QuerySnapshot snap = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: user.email)
          .limit(1)
          .get();

      if (snap.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("User doc not found.")),
        );
        return;
      }

      final docId = snap.docs.first.id;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(docId)
          .update({'status': newStatus});

      setState(() => _responderStatus = newStatus);
    } catch (e) {
      debugPrint("Status toggle error: $e");
    }
  }

  // ---------------------------------------------------------------
  // 🔥 REAL-TIME DISPATCH LISTENER
  // ---------------------------------------------------------------
 void _listenToDispatchStatus() {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final dispatchRef = FirebaseFirestore.instance
      .collection('dispatches')
      .where('responderEmails', arrayContains: user.email)
      .orderBy('timestamp', descending: true)
      .limit(1);

  _dispatchSub = dispatchRef.snapshots().listen((snapshot) async {
    if (snapshot.docs.isEmpty) {
      // No dispatch → ensure responder is Available (unless manually Unavailable)
      if (_responderStatus != "Unavailable") {
        await _updateUserStatus("Available");
      }

      setState(() {
        _dispatchStatus = "No Active Dispatch 🔒";
        _callerAddress = "";
      });

      return;
    }

    // There IS a dispatch
    final data = snapshot.docs.first.data();
    final status = data["status"];
    final address = data["userAddress"] ?? "";

    setState(() {
      _dispatchStatus = status;
      _callerAddress = address;
    });

    // UPDATE UI & Firestore BASED ON DISPATCH STATUS
    if (status == "Dispatched") {
      // Only set if not already dispatched
      if (_responderStatus != "Dispatched") {
        await _updateUserStatus("Dispatched");
      }
    }

    if (status == "Resolved") {
      // Automatically return responder to Available
      if (_responderStatus != "Unavailable") {
        await _updateUserStatus("Available");
      }

      // And show UI
      setState(() {
        _dispatchStatus = "Resolved";
      });
    }
  });
}


  // ---------------------------------------------------------------
  // 🔥 Load Recent Alerts
  // ---------------------------------------------------------------
  Future<void> _loadRecentAlerts() async {
    final query = await FirebaseFirestore.instance
        .collection('alerts')
        .orderBy('timestamp', descending: true)
        .limit(3)
        .get();

    final alerts = query.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    }).toList();

    setState(() {
      _recentAlerts = alerts;
    });
  }

  // TIME & DATE
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
      "January","February","March","April","May","June",
      "July","August","September","October","November","December"
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

  Future<void> _updateUserStatus(String newStatus) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  try {
    QuerySnapshot snap = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: user.email)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return;

    final docId = snap.docs.first.id;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(docId)
        .update({'status': newStatus});

    setState(() {
      _responderStatus = newStatus;
    });
  } catch (e) {
    debugPrint("UpdateUserStatus error: $e");
  }
}


  // ---------------------------------------------------------------
  //                     MAIN UI STARTS HERE
  // ---------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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

  // ---------------------------------------------------------------
  // Dashboard UI
  // ---------------------------------------------------------------
  Widget _buildDashboard(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Ready to Respond",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          _buildDispatchStatusCard(),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(child: _buildTimeCard()),
              const SizedBox(width: 12),
              Expanded(child: _buildStatusCard()),
            ],
          ),

          const SizedBox(height: 20),
          const Text("Recent Fire Incidents",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          Column(
            children: _recentAlerts.map((alert) {
              return _recentIncidentCard(alert);
            }).toList(),
          ),

          const SizedBox(height: 30),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // Status Toggle Card
  // ---------------------------------------------------------------
 Widget _buildStatusCard() {
  Color startColor, endColor;
  IconData icon;
  String displayText;

  if (_responderStatus == "Available") {
    startColor = Colors.green;
    endColor = Colors.greenAccent;
    icon = Icons.check_circle;
    displayText = "Available";
  } else if (_responderStatus == "Unavailable") {
    startColor = Colors.red;
    endColor = Colors.redAccent;
    icon = Icons.cancel;
    displayText = "Unavailable";
  } else if (_responderStatus == "Dispatched") {
    startColor = Colors.blue;
    endColor = Colors.lightBlueAccent;
    icon = Icons.local_fire_department;
    displayText = "Dispatched";
  } else {
    startColor = Colors.grey;
    endColor = Colors.blueGrey;
    icon = Icons.help_outline;
    displayText = _responderStatus;
  }

  return InkWell(
    onTap: _toggleResponderStatus,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [startColor, endColor]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(height: 8),
          Text(
            displayText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            "Tap to change",
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
    ),
  );
}


  // ---------------------------------------------------------------
  // Time Card UI
  // ---------------------------------------------------------------
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

  // ---------------------------------------------------------------
  // Recent Alerts UI
  // ---------------------------------------------------------------
  Widget _recentIncidentCard(Map<String, dynamic> alert) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: const Icon(Icons.local_fire_department, color: Colors.red),
        title: Text(alert['type'] ?? "Unknown Alert"),
        subtitle: Text("Address: ${alert['userAddress'] ?? 'N/A'}"),
        trailing: ElevatedButton(
          onPressed: () => _openAlertViewModal(alert),
          child: const Text("View"),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------
  // Modal for viewing alert details
  // ---------------------------------------------------------------
  void _openAlertViewModal(Map<String, dynamic> alert) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(20),
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("🔥 Incident Details",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),

              Text("Type: ${alert['type'] ?? 'Unknown'}"),
              Text("Location: ${alert['location'] ?? 'Unknown'}"),
              Text("Reporter: ${alert['userName'] ?? 'N/A'}"),
              Text("Contact: ${alert['userContact'] ?? 'N/A'}"),
              Text("Address: ${alert['userAddress'] ?? 'N/A'}"),

              const SizedBox(height: 12),

              if (alert['userLatitude'] != null &&
                  alert['userLongitude'] != null)
                Text("Coordinates: ${alert['userLatitude']}, ${alert['userLongitude']}"),

              const SizedBox(height: 12),

              const Text("🕒 Timestamp:",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text(alert['timestamp'] != null
                  ? DateTime.fromMillisecondsSinceEpoch(
                          alert['timestamp'].seconds * 1000)
                      .toString()
                  : "N/A"),

              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (alert['userLatitude'] != null &&
                      alert['userLongitude'] != null)
                    ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        await _openNavigationToAlert(
                          alertLat: (alert['userLatitude'] as num).toDouble(),
                          alertLng: (alert['userLongitude'] as num).toDouble(),
                        );
                      },
                      child: const Text("Navigate"),
                    ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Close"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------
  // DISPATCH Status Card UI
  // ---------------------------------------------------------------
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

                if (_callerAddress.isNotEmpty)
                  Text("Address: $_callerAddress",
                      style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),

          if (_dispatchStatus == "Dispatched") ...[
            ElevatedButton(
              onPressed: _openAlertDetails,
              child: const Text("View"),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _markAsResolved,
              child: const Text("Resolve"),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // View Dispatch Details
  // ---------------------------------------------------------------
  void _openAlertDetails() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final query = await FirebaseFirestore.instance
        .collection('dispatches')
        .where('responderEmails', arrayContains: user.email)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();

    if (query.docs.isEmpty) return;

    final data = query.docs.first.data();
    final alertId = data["alertId"];
    if (alertId == null) return;

    final snap = await FirebaseFirestore.instance
        .collection("alerts")
        .doc(alertId)
        .get();

    if (!snap.exists) return;

    setState(() {
      _alertData = snap.data();
      _showAlertModal = true;
    });
  }

  // ---------------------------------------------------------------
  // MARK AS RESOLVED
  // ---------------------------------------------------------------
  void _markAsResolved() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final query = await FirebaseFirestore.instance
        .collection('dispatches')
        .where('responderEmails', arrayContains: user.email)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();

    if (query.docs.isEmpty) return;

    final dispatchDoc = query.docs.first;
    final dispatchId = dispatchDoc.id;
    final data = dispatchDoc.data();

    final alertId = data["alertId"];
    final responders = data["responders"] as List<dynamic>;

    try {
      await FirebaseFirestore.instance
          .collection('dispatches')
          .doc(dispatchId)
          .update({'status': 'Resolved'});

      if (alertId != null) {
        await FirebaseFirestore.instance
            .collection('alerts')
            .doc(alertId)
            .update({'status': 'Resolved'});
      }

      for (var r in responders) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(r["id"])
            .update({'status': 'Available'});
      }

      setState(() => _dispatchStatus = "Resolved");

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Dispatch resolved.")),
      );
    } catch (e) {
      debugPrint("Error: $e");
    }
  }

  // ---------------------------------------------------------------
  // Alert Details Modal (for responder assigned alert)
  // ---------------------------------------------------------------
  Widget _alertDetailsModal() {
    if (_alertData == null) return const SizedBox();

    final a = _alertData!;
    final userLat =
        (a['userLatitude'] is num) ? (a['userLatitude'] as num).toDouble() : null;
    final userLng =
        (a['userLongitude'] is num) ? (a['userLongitude'] as num).toDouble() : null;

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

              Text("Type: ${a['type'] ?? 'Unknown'}"),
              Text("Location: ${a['location'] ?? 'Unknown'}"),
              Text("Status: ${a['status'] ?? 'Unknown'}"),

              const SizedBox(height: 12),
              const Text("👤 Reporter:",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text("Name: ${a['userName'] ?? 'N/A'}"),
              Text("Contact: ${a['userContact'] ?? 'N/A'}"),
              Text("Address: ${a['userAddress'] ?? 'N/A'}"),

              if (userLat != null && userLng != null) ...[
                const SizedBox(height: 8),
                Text("Coordinates: $userLat, $userLng"),
              ],

              const SizedBox(height: 12),

              const Text("🕒 Date & Time:",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text(a['timestamp'] != null
                  ? DateTime.fromMillisecondsSinceEpoch(
                          a['timestamp'].seconds * 1000)
                      .toString()
                  : "N/A"),

              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (userLat != null && userLng != null)
                    ElevatedButton(
                      onPressed: () async {
                        await _openNavigationToAlert(
                            alertLat: userLat, alertLng: userLng);
                      },
                      child: const Text("Navigate"),
                    ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Close"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------
  // NAVIGATION → Uses EXACT email match
  // ---------------------------------------------------------------
  Future<void> _openNavigationToAlert({
    required double alertLat,
    required double alertLng,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      QuerySnapshot snap = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: user.email) // FIXED
          .limit(1)
          .get();

      if (snap.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Responder record not found.")),
        );
        return;
      }

      final doc = snap.docs.first.data() as Map<String, dynamic>;
      final resLat = (doc['latitude'] as num?)?.toDouble();
      final resLng = (doc['longitude'] as num?)?.toDouble();

      if (resLat == null || resLng == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Responder coordinates missing.")),
        );
        return;
      }

      await _launchMapsDirections(
        originLat: resLat,
        originLng: resLng,
        destLat: alertLat,
        destLng: alertLng,
      );
    } catch (e) {
      debugPrint("Navigation error: $e");
    }
  }

  // Build Maps directions URI and launch external app / browser.
  Future<void> _launchMapsDirections({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    final url = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&origin=$originLat,$originLng&destination=$destLat,$destLng&travelmode=driving');

    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not open maps.")),
      );
    }
  }
}
