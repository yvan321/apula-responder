// lib/screens/app/home/home_page.dart
import 'dart:async';
import 'dart:io';

import 'package:apula_responder/screens/app/dispatch/dispatch_page.dart';
import 'package:apula_responder/screens/app/map/map_navigation_page.dart';
import 'package:apula_responder/screens/app/notifications/notification_page.dart';
import 'package:apula_responder/screens/app/settings/settings_page.dart';
import 'package:apula_responder/widgets/custom_bottom_nav.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
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
  String? _lastDispatchId;

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

  // ------------------------
  // Audio & Notification
  // ------------------------
  final AudioPlayer _player = AudioPlayer();
  bool _hasPlayedSound = false;
  int _unreadNotifCount = 0;

  // ------------------------
  // Backup Request State
  // ------------------------
  bool _isRequestingBackup = false;
  bool _hasPendingBackupRequest = false;
  int _currentWaveNumber = 1;
  String? _currentDispatchId;
  String? _currentAlertId;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();

    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
    _listenToDispatchStatus();
    _loadRecentAlerts();
    _getResponderStatus();
    _listenUnreadNotifications();
    _initializeLocalNotifications();
  }

  Future<void> _initializeLocalNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: android);
    try {
      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (response) {},
      );
    } catch (e) {
      debugPrint("Local notifications init error: $e");
    }
  }

  void _listenUnreadNotifications() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    FirebaseFirestore.instance
        .collection('dispatches')
        .where('responderEmails', arrayContains: user.email)
        .where('read', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _unreadNotifCount = snapshot.docs.length;
      });
    });
  }

  Future<String?> _downloadAndSaveImage(String url, String fileName) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/$fileName';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        return filePath;
      } else {
        debugPrint("Image HTTP error: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Image download failed: $e");
    }
    return null;
  }

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
        if (!mounted) return;
        setState(() {
          _responderStatus = data['status'] ?? "Available";
        });
      }
    } catch (e) {
      debugPrint("Status load error: $e");
    }
  }

  Future<void> _toggleResponderStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    String newStatus;

    if (_responderStatus == "Available") {
      newStatus = "Unavailable";
    } else if (_responderStatus == "Unavailable") {
      newStatus = "Available";
    } else if (_responderStatus == "Dispatched") {
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

      await FirebaseFirestore.instance.collection('users').doc(docId).update({
        'status': newStatus,
      });

      if (!mounted) return;
      setState(() => _responderStatus = newStatus);
    } catch (e) {
      debugPrint("Status toggle error: $e");
    }
  }

  Future<void> _checkPendingBackupRequest(String dispatchId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('backup_requests')
          .where('sourceDispatchId', isEqualTo: dispatchId)
          .where('status', isEqualTo: 'Pending')
          .limit(1)
          .get();

      if (!mounted) return;
      setState(() {
        _hasPendingBackupRequest = snap.docs.isNotEmpty;
      });
    } catch (e) {
      debugPrint("Check backup request error: $e");
    }
  }

  // ✅ NO dispatches composite query here anymore
  Future<void> _requestBackup() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (_isRequestingBackup) return;

    if (_currentDispatchId == null || _currentAlertId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No active dispatch found.")),
      );
      return;
    }

    setState(() => _isRequestingBackup = true);

    try {
      final dispatchDoc = await FirebaseFirestore.instance
          .collection('dispatches')
          .doc(_currentDispatchId)
          .get();

      if (!dispatchDoc.exists) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Dispatch record not found.")),
        );
        return;
      }

      final dispatchData = dispatchDoc.data() as Map<String, dynamic>;

      if (dispatchData['status'] != 'Dispatched') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Backup can only be requested while dispatched."),
          ),
        );
        return;
      }

      final existing = await FirebaseFirestore.instance
          .collection('backup_requests')
          .where('sourceDispatchId', isEqualTo: _currentDispatchId)
          .where('status', isEqualTo: 'Pending')
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        if (!mounted) return;

        setState(() {
          _hasPendingBackupRequest = true;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Backup request already sent.")),
        );
        return;
      }

      final responderSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: user.email)
          .limit(1)
          .get();

      String responderName = "Responder";
      if (responderSnap.docs.isNotEmpty) {
        final responderData =
            responderSnap.docs.first.data() as Map<String, dynamic>;
        responderName = responderData['name'] ?? "Responder";
      }

      await FirebaseFirestore.instance.collection('backup_requests').add({
        'alertId': _currentAlertId,
        'sourceDispatchId': _currentDispatchId,
        'requestedWaveNumber': _currentWaveNumber + 1,
        'requestedByName': responderName,
        'requestedByEmail': user.email,
        'reason': 'Fire too strong',
        'status': 'Pending',
        'approvedDispatchId': '',
        'approvedBy': '',
        'timestamp': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance
          .collection('alerts')
          .doc(_currentAlertId)
          .update({
        'backupRequestCount': FieldValue.increment(1),
      });

      if (!mounted) return;

      setState(() {
        _hasPendingBackupRequest = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Backup request sent to admin.")),
      );
    } catch (e) {
      debugPrint("Request backup error: $e");

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to request backup: $e")),
      );
    } finally {
      if (mounted) {
        setState(() => _isRequestingBackup = false);
      }
    }
  }

  void _listenToDispatchStatus() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final dispatchRef = FirebaseFirestore.instance
        .collection('dispatches')
        .where('responderEmails', arrayContains: user.email)
        .orderBy('timestamp', descending: true)
        .limit(1);

    _dispatchSub = dispatchRef.snapshots().listen(
      (snapshot) async {
        if (snapshot.docs.isEmpty) {
          if (_responderStatus != "Unavailable") {
            await _updateUserStatus("Available");
          }

          if (!mounted) return;
          setState(() {
            _dispatchStatus = "No Active Dispatch 🔒";
            _callerAddress = "";
            _currentDispatchId = null;
            _currentAlertId = null;
            _currentWaveNumber = 1;
            _hasPendingBackupRequest = false;
          });

          _hasPlayedSound = false;
          return;
        }

        final docSnap = snapshot.docs.first;
        final data = docSnap.data();
        final status = data["status"];
        final address = data["userAddress"] ?? "";

        final dynamic rawWave = data["waveNumber"];
        final int parsedWave =
            rawWave is int ? rawWave : int.tryParse(rawWave.toString()) ?? 1;

        if (!mounted) return;
        setState(() {
          _dispatchStatus = status;
          _callerAddress = address;
          _currentDispatchId = docSnap.id;
          _currentAlertId = data["alertId"];
          _currentWaveNumber = parsedWave;
        });

        if (status == "Dispatched") {
          final newDispatchId = docSnap.id;

          if (_lastDispatchId != newDispatchId) {
            _lastDispatchId = newDispatchId;

            debugPrint("🔥 NEW DISPATCH DETECTED");
            debugPrint("📍 Address: $address");

            _playDispatchSound();
            _showDispatchNotification();
          }

          await _checkPendingBackupRequest(newDispatchId);

          if (_responderStatus != "Dispatched") {
            await _updateUserStatus("Dispatched");
          }
        }

        if (status == "Resolved") {
          _hasPlayedSound = false;

          if (_responderStatus != "Unavailable") {
            await _updateUserStatus("Available");
          }

          if (!mounted) return;
          setState(() {
            _dispatchStatus = "Resolved";
            _hasPendingBackupRequest = false;
          });
        }
      },
      onError: (e) {
        debugPrint("Dispatch listen error: $e");
      },
    );
  }

  Future<void> _playDispatchSound() async {
    try {
      await _player.play(AssetSource('sounds/fire_alarm.mp3'));
    } catch (e) {
      debugPrint("Error playing sound: $e");
    }
  }

  Future<void> _showDispatchNotification() async {
    try {
      String? imagePath;

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final query = await FirebaseFirestore.instance
          .collection('dispatches')
          .where('responderEmails', arrayContains: user.email)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      String address = "Active fire incident";

      if (query.docs.isNotEmpty) {
        final data = query.docs.first.data();

        address = data['userAddress'] ?? address;

        final snapshotUrl = data['snapshotUrl'];

        if (snapshotUrl != null && snapshotUrl.toString().isNotEmpty) {
          imagePath = await _downloadAndSaveImage(
            snapshotUrl,
            "dispatch_image.jpg",
          );
        }
      }

      AndroidNotificationDetails androidDetails;

      if (imagePath != null) {
        final bigPictureStyle = BigPictureStyleInformation(
          FilePathAndroidBitmap(imagePath),
          contentTitle: '🚨 FIRE DISPATCH',
          summaryText: address,
        );

        androidDetails = AndroidNotificationDetails(
          'high_importance_channel',
          'High Importance Notifications',
          channelDescription: 'Used for critical dispatcher alerts',
          importance: Importance.max,
          priority: Priority.max,
          styleInformation: bigPictureStyle,
          playSound: true,
          icon: '@mipmap/ic_launcher',
        );
      } else {
        androidDetails = const AndroidNotificationDetails(
          'high_importance_channel',
          'High Importance Notifications',
          channelDescription: 'Used for critical dispatcher alerts',
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          icon: '@mipmap/ic_launcher',
        );
      }

      final notificationDetails = NotificationDetails(android: androidDetails);

      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        '🚨 DISPATCH ALERT',
        address,
        notificationDetails,
        payload: 'dispatch',
      );
    } catch (e) {
      debugPrint("Notification error: $e");
    }
  }

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

    if (!mounted) return;
    setState(() {
      _recentAlerts = alerts;
    });
  }

  void _updateTime() {
    final now = DateTime.now();
    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final period = now.hour >= 12 ? "PM" : "AM";

    if (!mounted) return;
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
    _dispatchSub?.cancel();
    _player.dispose();
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

      await FirebaseFirestore.instance.collection('users').doc(docId).update({
        'status': newStatus,
      });

      if (!mounted) return;
      setState(() {
        _responderStatus = newStatus;
      });
    } catch (e) {
      debugPrint("UpdateUserStatus error: $e");
    }
  }

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
                children: [Image.asset("assets/logo.png", height: 100)],
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
        notifCount: _unreadNotifCount,
      ),
    );
  }

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
          const Text(
            "Recent Fire Incidents",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
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
            Text("Tap to change", style: TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _isDay
                ? [Colors.yellow.shade200, Colors.orange.shade300]
                : [Colors.indigo.shade700, Colors.indigo.shade900],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              _isDay ? Icons.wb_sunny : Icons.nightlight_round,
              color: _isDay ? Colors.black : Colors.white,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              _time,
              style: TextStyle(
                color: _isDay ? Colors.black : Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              _date,
              style: TextStyle(
                color: (_isDay ? Colors.black : Colors.white).withOpacity(0.7),
              ),
            ),
          ],
        ),
      );

  Widget _recentIncidentCard(Map<String, dynamic> alert) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.red, Colors.orange],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.local_fire_department,
            color: Colors.white,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              alert['userAddress'] ?? "Unknown Address",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.normal,
              ),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: () {
              _openAlertViewModal(alert);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text("View"),
          ),
        ],
      ),
    );
  }

  void _stopAlarm() {
    try {
      _player.stop();
    } catch (_) {}

    _hasPlayedSound = true;
  }

  void _openAlertViewModal(Map<String, dynamic> alert) {
    final snapshotUrl = alert['snapshotUrl'];
    final userLat = (alert['userLatitude'] as num?)?.toDouble();
    final userLng = (alert['userLongitude'] as num?)?.toDouble();

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: 350,
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.black12)),
                ),
                child: const Text(
                  "🔥 Incident Details",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (snapshotUrl != null &&
                          snapshotUrl.toString().isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            snapshotUrl,
                            height: 210,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return const SizedBox(
                                height: 210,
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                height: 210,
                                color: Colors.black12,
                                child: const Center(
                                  child: Icon(Icons.broken_image, size: 40),
                                ),
                              );
                            },
                          ),
                        ),
                      if (snapshotUrl != null) const SizedBox(height: 18),
                      Text("Type: ${alert['type'] ?? 'Unknown'}"),
                      Text("Location: ${alert['location'] ?? 'Unknown'}"),
                      Text("Reporter: ${alert['userName'] ?? 'N/A'}"),
                      Text("Contact: ${alert['userContact'] ?? 'N/A'}"),
                      Text("Address: ${alert['userAddress'] ?? 'N/A'}"),
                      const SizedBox(height: 12),
                      if (userLat != null && userLng != null)
                        Text("Coordinates: $userLat, $userLng"),
                      const SizedBox(height: 14),
                      const Text(
                        "🕒 Timestamp:",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        alert['timestamp'] != null
                            ? DateTime.fromMillisecondsSinceEpoch(
                                alert['timestamp'].seconds * 1000,
                              ).toString()
                            : "N/A",
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.black12)),
                ),
                child: Row(
                  children: [
                    if (userLat != null && userLng != null)
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            Navigator.pop(context);
                            await _openNavigationToAlert(
                              alertLat: userLat,
                              alertLng: userLng,
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFA30000),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text("Navigate"),
                        ),
                      ),
                    if (userLat != null && userLng != null)
                      const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text("Close"),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _dispatchStatus,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_callerAddress.isNotEmpty)
                      Text(
                        "Address: $_callerAddress",
                        style: const TextStyle(color: Colors.white70),
                      ),
                    if (_dispatchStatus == "Dispatched")
                      Text(
                        "Wave: $_currentWaveNumber",
                        style: const TextStyle(color: Colors.white70),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (_dispatchStatus == "Dispatched") ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      _stopAlarm();
                      _openAlertDetails();
                    },
                    child: const Text("View"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _markAsResolved,
                    child: const Text("Resolve"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_hasPendingBackupRequest || _isRequestingBackup)
                    ? null
                    : _requestBackup,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black87,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: _isRequestingBackup
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.group_add),
                label: Text(
                  _hasPendingBackupRequest
                      ? "Backup Requested"
                      : "Request Backup",
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ✅ NO dispatches query here anymore
  void _openAlertDetails() async {
    if (_currentAlertId == null) return;

    final snap = await FirebaseFirestore.instance
        .collection("alerts")
        .doc(_currentAlertId)
        .get();

    if (!snap.exists) return;

    if (!mounted) return;
    setState(() {
      _alertData = snap.data();
      _showAlertModal = true;
    });
  }

  // ✅ NO dispatches query here anymore
  void _markAsResolved() async {
  if (_currentDispatchId == null) return;

  try {
    final currentDispatch = await FirebaseFirestore.instance
        .collection('dispatches')
        .doc(_currentDispatchId)
        .get();

    if (!currentDispatch.exists) return;

    final currentData = currentDispatch.data() as Map<String, dynamic>;
    final alertId = currentData["alertId"];

    if (alertId == null) return;

    // Get ALL dispatches under the same alert
    final dispatches = await FirebaseFirestore.instance
        .collection('dispatches')
        .where('alertId', isEqualTo: alertId)
        .get();

    final batch = FirebaseFirestore.instance.batch();

    final Set<String> responderIds = {};
    final Set<String> teamIds = {};
    final Set<String> teamNames = {};

    for (final doc in dispatches.docs) {
      final data = doc.data();

      // Resolve dispatch
      batch.update(doc.reference, {
        'status': 'Resolved',
      });

      final responders = (data["responders"] as List<dynamic>? ?? []);

      for (final r in responders) {
        if (r["id"] != null) {
          responderIds.add(r["id"]);
        }

        if (r["teamId"] != null) {
          teamIds.add(r["teamId"]);
        }

        if (r["team"] != null) {
          teamNames.add(r["team"]);
        }
      }
    }

    // Resolve alert
    batch.update(
      FirebaseFirestore.instance.collection('alerts').doc(alertId),
      {'status': 'Resolved'},
    );

    // Reset responders
    for (final id in responderIds) {
      batch.update(
        FirebaseFirestore.instance.collection('users').doc(id),
        {'status': 'Available'},
      );
    }

    // Reset teams
    for (final id in teamIds) {
      batch.update(
        FirebaseFirestore.instance.collection('teams').doc(id),
        {'status': 'Available'},
      );
    }

    // Reset vehicles
    for (final teamName in teamNames) {
      final vehicles = await FirebaseFirestore.instance
          .collection('vehicles')
          .where('assignedTeam', isEqualTo: teamName)
          .get();

      for (final v in vehicles.docs) {
        batch.update(v.reference, {'status': 'Available'});
      }
    }

    await batch.commit();

    if (!mounted) return;

    setState(() {
      _dispatchStatus = "Resolved";
      _hasPendingBackupRequest = false;
      _currentDispatchId = null;
      _currentAlertId = null;
      _currentWaveNumber = 1;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Incident resolved. All teams cleared."),
      ),
    );
  } catch (e) {
    debugPrint("Resolve error: $e");

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Failed to resolve incident: $e")),
    );
  }
}

  Widget _infoRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "$label: ",
            style: const TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          Expanded(
            child: Text(
              value?.toString() ?? "N/A",
              style: const TextStyle(fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _alertDetailsModal() {
    _stopAlarm();
    if (_alertData == null) return const SizedBox();

    final a = _alertData!;
    final userLat = (a['userLatitude'] is num)
        ? (a['userLatitude'] as num).toDouble()
        : null;
    final userLng = (a['userLongitude'] is num)
        ? (a['userLongitude'] as num).toDouble()
        : null;
    final snapshotUrl = a['snapshotUrl'];

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 380,
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.black12)),
              ),
              child: const Text(
                "Alert Details",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (snapshotUrl != null &&
                        snapshotUrl.toString().isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          snapshotUrl,
                          height: 210,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return const SizedBox(
                              height: 210,
                              child: Center(child: CircularProgressIndicator()),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              height: 210,
                              color: Colors.black12,
                              child: const Center(
                                child: Icon(Icons.broken_image, size: 45),
                              ),
                            );
                          },
                        ),
                      ),
                    if (snapshotUrl != null) const SizedBox(height: 20),
                    _infoRow("Type", a['type']),
                    _infoRow("Status", a['status']),
                    _infoRow("Location", a['location']),
                    const SizedBox(height: 16),
                    const Text(
                      "Reporter Information",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const Divider(),
                    _infoRow("Name", a['userName']),
                    _infoRow("Contact", a['userContact']),
                    _infoRow("Address", a['userAddress']),
                    if (userLat != null && userLng != null)
                      _infoRow("Coordinates", "$userLat, $userLng"),
                    const SizedBox(height: 16),
                    const Text(
                      "Timestamp",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const Divider(),
                    Text(
                      a['timestamp'] != null
                          ? DateTime.fromMillisecondsSinceEpoch(
                              a['timestamp'].seconds * 1000,
                            ).toString()
                          : "N/A",
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Colors.black12)),
              ),
              child: Row(
                children: [
                  if (userLat != null && userLng != null)
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          await _openNavigationToAlert(
                            alertLat: userLat,
                            alertLng: userLng,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFA30000),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text("Navigate"),
                      ),
                    ),
                  if (userLat != null && userLng != null)
                    const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text("Close"),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openNavigationToAlert({
    required double alertLat,
    required double alertLng,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      QuerySnapshot snap = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: user.email)
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

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MapNavigationPage(
            responderLat: resLat,
            responderLng: resLng,
            alertLat: alertLat,
            alertLng: alertLng,
            apiKey: "AIzaSyC4Ai-W_V2M7qftiuQBYcnyCL8oqaDF680",
          ),
        ),
      );
    } catch (e) {
      debugPrint("Navigation error: $e");
    }
  }

  Future<void> _launchMapsDirections({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&origin=$originLat,$originLng&destination=$destLat,$destLng&travelmode=driving',
    );

    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not open maps.")),
      );
    }
  }
}