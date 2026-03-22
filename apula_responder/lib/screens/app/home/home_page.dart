// lib/screens/app/home/home_page.dart
import 'dart:async';
import 'dart:convert';
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
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
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

  String _dispatchStatus = "Loading...";
  StreamSubscription? _dispatchSub;
  String _callerAddress = "";

  List<Map<String, dynamic>> _recentAlerts = [];

  String _responderStatus = "Available";

  final AudioPlayer _player = AudioPlayer();
  bool _hasPlayedSound = false;
  int _unreadNotifCount = 0;

  bool _isRequestingBackup = false;
  bool _hasPendingBackupRequest = false;
  int _currentWaveNumber = 1;
  String? _currentDispatchId;
  String? _currentAlertId;

  bool _isTeamLeader = false;

  String _userName = "Responder";
  String _teamName = "No Team";

  double? _currentTemp;
  String _weatherTitle = "Loading...";
  String _weatherLocation = "Getting location...";
  bool _weatherLoading = true;
  int? _weatherCode;

  String? _currentAlertType;
  String _currentDispatchTimestampText = "";

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
    _loadWeatherCardData();
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

  Future<String?> _downloadAndSaveImage(
    dynamic imageSource,
    String fileName,
  ) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/$fileName';

      if (imageSource == null) return null;

      String value = imageSource.toString().trim();
      if (value.isEmpty) return null;

      List<int> bytes;

      if (value.startsWith('http://') || value.startsWith('https://')) {
        final response = await http.get(Uri.parse(value));

        if (response.statusCode != 200) {
          debugPrint("Image HTTP error: ${response.statusCode}");
          return null;
        }

        bytes = response.bodyBytes;
      } else {
        if (value.startsWith('data:image')) {
          final commaIndex = value.indexOf(',');
          if (commaIndex == -1) return null;
          value = value.substring(commaIndex + 1).trim();
        }

        value = value.replaceAll(RegExp(r'\s+'), '');
        bytes = base64Decode(value);
      }

      final file = File(filePath);
      await file.writeAsBytes(bytes);
      return filePath;
    } catch (e) {
      debugPrint("Image save failed: $e");
      return null;
    }
  }

  Widget _modernInfoCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFF2F2F7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFFB71C1C), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF1C1C1E),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSnapshotImage(dynamic snapshotUrl) {
    final fallback = Container(
      height: 210,
      width: double.infinity,
      color: Colors.black12,
      child: const Center(child: Icon(Icons.broken_image, size: 40)),
    );

    if (snapshotUrl == null) return fallback;

    String value = snapshotUrl.toString().trim();
    if (value.isEmpty) return fallback;

    try {
      if (value.startsWith('http://') || value.startsWith('https://')) {
        return Image.network(
          value,
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
            debugPrint("Image.network error: $error");
            return fallback;
          },
        );
      }

      if (value.startsWith('data:image')) {
        final commaIndex = value.indexOf(',');
        if (commaIndex == -1) return fallback;
        value = value.substring(commaIndex + 1).trim();
      }

      value = value.replaceAll(RegExp(r'\s+'), '');

      final bytes = base64Decode(value);

      return Image.memory(
        bytes,
        height: 210,
        width: double.infinity,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) {
          debugPrint("Image.memory error: $error");
          return fallback;
        },
      );
    } catch (e) {
      debugPrint("Snapshot decode error: $e");
      return fallback;
    }
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?>
  _getCurrentUserDoc() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return null;

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: user.email)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;
    return snap.docs.first;
  }

  Future<bool> _resolveLeaderForDispatch(
    String dispatchId,
    Map<String, dynamic> dispatchData,
  ) async {
    try {
      final currentUserDoc = await _getCurrentUserDoc();
      if (currentUserDoc == null) return false;

      final currentUserId = currentUserDoc.id;
      final currentUserEmail = (currentUserDoc.data()['email'] ?? '')
          .toString()
          .toLowerCase();

      final dispatchLeaderId = dispatchData['leaderId'];
      if (dispatchLeaderId != null &&
          dispatchLeaderId.toString().trim().isNotEmpty) {
        return dispatchLeaderId.toString() == currentUserId;
      }

      String? teamId;
      String? teamName;

      final members = dispatchData['members'];
      if (members is List) {
        for (final m in members) {
          if (m is Map) {
            final memberId = (m['id'] ?? '').toString();
            final memberEmail = (m['email'] ?? '').toString().toLowerCase();
            if (memberId == currentUserId || memberEmail == currentUserEmail) {
              teamId = (m['teamId'] ?? '').toString();
              teamName = (m['teamName'] ?? '').toString();
              break;
            }
          }
        }
      }

      final responders = dispatchData['responders'];
      if ((teamId == null || teamId.isEmpty) &&
          (teamName == null || teamName.isEmpty) &&
          responders is List) {
        for (final r in responders) {
          if (r is Map) {
            final responderId = (r['id'] ?? '').toString();
            final responderEmail = (r['email'] ?? '').toString().toLowerCase();
            if (responderId == currentUserId ||
                responderEmail == currentUserEmail) {
              teamId = (r['teamId'] ?? '').toString();
              teamName = (r['team'] ?? r['teamName'] ?? '').toString();
              break;
            }
          }
        }
      }

      teamId ??= (dispatchData['teamId'] ?? '').toString();
      teamName ??= (dispatchData['teamName'] ?? '').toString();

      if (teamId.isNotEmpty) {
        final teamDoc = await FirebaseFirestore.instance
            .collection('teams')
            .doc(teamId)
            .get();

        if (teamDoc.exists) {
          final teamData = teamDoc.data() as Map<String, dynamic>;
          final leaderId = (teamData['leaderId'] ?? '').toString();
          return leaderId == currentUserId;
        }
      }

      if (teamName.isNotEmpty) {
        final teamSnap = await FirebaseFirestore.instance
            .collection('teams')
            .where('teamName', isEqualTo: teamName)
            .limit(1)
            .get();

        if (teamSnap.docs.isNotEmpty) {
          final teamData = teamSnap.docs.first.data();
          final leaderId = (teamData['leaderId'] ?? '').toString();
          return leaderId == currentUserId;
        }
      }

      return false;
    } catch (e) {
      debugPrint("Leader resolve error: $e");
      return false;
    }
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
          _userName = data['name'] ?? "Responder";
          _teamName = data['teamName'] ?? "No Team";
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("User doc not found.")));
        return;
      }

      final docData = snap.docs.first.data() as Map<String, dynamic>;
      final docId = snap.docs.first.id;

      await FirebaseFirestore.instance.collection('users').doc(docId).update({
        'status': newStatus,
      });

      if (!mounted) return;
      setState(() {
        _responderStatus = newStatus;
        _userName = docData['name'] ?? _userName;
        _teamName = docData['teamName'] ?? _teamName;
      });
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

  Future<void> _requestBackup() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (!_isTeamLeader) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Only the team leader can request backup."),
        ),
      );
      return;
    }

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
          .update({'backupRequestCount': FieldValue.increment(1)});

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to request backup: $e")));
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
            _isTeamLeader = false;
          });

          _hasPlayedSound = false;
          return;
        }

        final docSnap = snapshot.docs.first;
        final data = docSnap.data();
        final status = data["status"];
        final address = data["userAddress"] ?? "";
        final alertType = data["type"] ?? data["alertType"] ?? "Unknown";

        String dispatchTimestampText = "";
        final ts = data["timestamp"];
        if (ts is Timestamp) {
          final dt = ts.toDate();
          final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
          final minute = dt.minute.toString().padLeft(2, '0');
          final period = dt.hour >= 12 ? "PM" : "AM";
          dispatchTimestampText =
              "${_monthName(dt.month)} ${dt.day}, ${dt.year} $hour:$minute $period";
        }

        final dynamic rawWave = data["waveNumber"];
        final int parsedWave = rawWave is int
            ? rawWave
            : int.tryParse(rawWave.toString()) ?? 1;

        final bool leader = await _resolveLeaderForDispatch(docSnap.id, data);

        if (!mounted) return;
        setState(() {
          _dispatchStatus = status;
          _callerAddress = address;
          _currentDispatchId = docSnap.id;
          _currentAlertId = data["alertId"];
          _currentWaveNumber = parsedWave;
          _isTeamLeader = leader;
          _currentAlertType = alertType.toString();
          _currentDispatchTimestampText = dispatchTimestampText;
        });

        if (status == "Dispatched") {
          final newDispatchId = docSnap.id;

          if (_lastDispatchId != newDispatchId) {
            _lastDispatchId = newDispatchId;

            debugPrint("🔥 NEW DISPATCH DETECTED");
            debugPrint("📍 Address: $address");
            debugPrint("👑 Is Leader: $leader");

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
            _isTeamLeader = false;
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

        final snapshotUrl =
            data['snapshotUrl'] ??
            data['snapshotBase64'] ??
            data['imageBase64'] ??
            data['photo'];

        if (snapshotUrl != null && snapshotUrl.toString().trim().isNotEmpty) {
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
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return;

    try {
      final query = await FirebaseFirestore.instance
          .collection('dispatches')
          .where('responderEmails', arrayContains: user.email)
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
    } catch (e) {
      debugPrint("Recent responder dispatch load error: $e");
    }
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

  Future<void> _loadWeatherCardData() async {
    try {
      if (!mounted) return;
      setState(() {
        _weatherLoading = true;
      });

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        setState(() {
          _weatherTitle = "Location Off";
          _weatherLocation = "Enable location services";
          _weatherLoading = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _weatherTitle = "Permission Needed";
          _weatherLocation = "Location access denied";
          _weatherLoading = false;
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      String cityName = "Unknown location";
      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          cityName = place.locality?.trim().isNotEmpty == true
              ? place.locality!
              : (place.subAdministrativeArea?.trim().isNotEmpty == true
                    ? place.subAdministrativeArea!
                    : (place.administrativeArea ?? "Unknown location"));
        }
      } catch (_) {}

      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=${position.latitude}'
        '&longitude=${position.longitude}'
        '&current=temperature_2m,weather_code,is_day'
        '&timezone=auto',
      );

      final response = await http.get(uri);

      if (response.statusCode != 200) {
        if (!mounted) return;
        setState(() {
          _weatherTitle = "Weather Unavailable";
          _weatherLocation = cityName;
          _weatherLoading = false;
        });
        return;
      }

      final data = jsonDecode(response.body);
      final current = data['current'];

      final temp = (current['temperature_2m'] as num?)?.toDouble();
      final code = current['weather_code'] as int?;
      final isDayValue = current['is_day'] == 1;

      if (!mounted) return;
      setState(() {
        _currentTemp = temp;
        _weatherCode = code;
        _weatherTitle = _mapWeatherTitle(code, isDayValue);
        _weatherLocation = cityName;
        _weatherLoading = false;
      });
    } catch (e) {
      debugPrint("Weather card load error: $e");
      if (!mounted) return;
      setState(() {
        _weatherTitle = "Weather Error";
        _weatherLocation = "Try again later";
        _weatherLoading = false;
      });
    }
  }

  String _mapWeatherTitle(int? code, bool isDayValue) {
    switch (code) {
      case 0:
        return isDayValue ? "Sunny" : "Clear Night";
      case 1:
      case 2:
      case 3:
        return isDayValue ? "Cloudy" : "Cloudy Night";
      case 45:
      case 48:
        return "Foggy";
      case 51:
      case 53:
      case 55:
      case 56:
      case 57:
        return "Drizzle";
      case 61:
      case 63:
      case 65:
      case 80:
      case 81:
      case 82:
        return "Rain";
      case 66:
      case 67:
        return "Freezing Rain";
      case 71:
      case 73:
      case 75:
      case 77:
      case 85:
      case 86:
        return "Snow";
      case 95:
      case 96:
      case 99:
        return "Thunderstorm";
      default:
        return isDayValue ? "Weather" : "Night Weather";
    }
  }

  List<Color> _weatherGradient() {
    final title = _weatherTitle.toLowerCase();

    if (title.contains("rain") || title.contains("drizzle")) {
      return const [Color(0xFF11C1B0), Color(0xFF64F38C)];
    }

    if (title.contains("night")) {
      return const [Color(0xFF2F62F2), Color(0xFFB57BE8)];
    }

    if (title.contains("cloud")) {
      return const [Color(0xFF4A90E2), Color(0xFF8BC6FF)];
    }

    if (title.contains("thunder")) {
      return const [Color(0xFF5C6BC0), Color(0xFF8E24AA)];
    }

    return const [Color(0xFF2196F3), Color(0xFF7EC8FF)];
  }

  IconData _weatherMainIcon() {
    final title = _weatherTitle.toLowerCase();

    if (title.contains("rain") || title.contains("drizzle")) {
      return Icons.thunderstorm_rounded;
    }

    if (title.contains("night")) {
      return Icons.nightlight_round;
    }

    if (title.contains("cloud")) {
      return Icons.cloud_rounded;
    }

    if (title.contains("thunder")) {
      return Icons.flash_on_rounded;
    }

    return Icons.wb_sunny_rounded;
  }

  Widget _weatherDecorationIcon() {
    final title = _weatherTitle.toLowerCase();

    if (title.contains("rain") || title.contains("drizzle")) {
      return Icon(
        Icons.cloudy_snowing,
        size: 86,
        color: Colors.white.withOpacity(0.88),
      );
    }

    if (title.contains("night")) {
      return Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.cloud_rounded,
            size: 86,
            color: Colors.white.withOpacity(0.80),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: Icon(
              Icons.nightlight_round,
              size: 42,
              color: Colors.amber.shade200,
            ),
          ),
        ],
      );
    }

    if (title.contains("cloud")) {
      return Icon(
        Icons.cloud_rounded,
        size: 86,
        color: Colors.white.withOpacity(0.88),
      );
    }

    return Icon(Icons.wb_sunny_rounded, size: 86, color: Colors.amber.shade200);
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

      final data = snap.docs.first.data() as Map<String, dynamic>;
      final docId = snap.docs.first.id;

      await FirebaseFirestore.instance.collection('users').doc(docId).update({
        'status': newStatus,
      });

      if (!mounted) return;
      setState(() {
        _responderStatus = newStatus;
        _userName = data['name'] ?? _userName;
        _teamName = data['teamName'] ?? _teamName;
      });
    } catch (e) {
      debugPrint("UpdateUserStatus error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
          _buildTimeCard(),
          const SizedBox(height: 16),
          _buildDispatchStatusCard(),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildResponderInfoCard()),
              const SizedBox(width: 12),
              Expanded(child: _buildStatusCard()),
            ],
          ),
          const SizedBox(height: 20),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Recent Fire Incidents",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _selectedIndex = 1;
                  });
                },
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFB71C1C),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  "View all",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ],
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

  Widget _buildTimeCard() {
    final gradientColors = _weatherGradient();
    final tempText = _weatherLoading
        ? "--"
        : (_currentTemp != null ? _currentTemp!.round().toString() : "--");

    return Container(
      height: 130,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: gradientColors.last.withOpacity(0.28),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(
          children: [
            Positioned(
              right: -30,
              top: -10,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.10),
                ),
              ),
            ),
            Positioned(
              right: 10,
              top: 0,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.08),
                ),
              ),
            ),
            Positioned(right: 16, top: 20, child: _weatherDecorationIcon()),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _weatherTitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.95),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tempText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 58,
                              fontWeight: FontWeight.w300,
                              height: 1,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Text(
                              "°",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Container(
                        width: 1.2,
                        height: 58,
                        color: Colors.white.withOpacity(0.22),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 70),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _date,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.95),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(
                                    Icons.access_time_filled_rounded,
                                    size: 15,
                                    color: Colors.white.withOpacity(0.90),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _time,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.92),
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.location_on,
                                    size: 15,
                                    color: Colors.white.withOpacity(0.90),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _weatherLocation,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.92),
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResponderInfoCard() {
    final String firstName = _userName.trim().isEmpty
        ? "Responder"
        : _userName.trim().split(RegExp(r'\s+')).first;

    return Container(
      height: 145,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF3E0), Color(0xFFFFE0B2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFB74D).withOpacity(0.22),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFB74D), Color(0xFFFF8A65)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Center(
                child: Icon(
                  Icons.fire_truck_rounded,
                  color: Colors.white,
                  size: 50,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            firstName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF4E342E),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            "Team $_teamName",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF6D4C41),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    Color startColor;
    Color endColor;
    IconData icon;
    String title;

    if (_responderStatus == "Available") {
      startColor = const Color(0xFF43A047);
      endColor = const Color(0xFF69F0AE);
      icon = Icons.check_circle_rounded;
      title = "Available";
    } else if (_responderStatus == "Unavailable") {
      startColor = const Color(0xFFD32F2F);
      endColor = const Color(0xFFFF6E6E);
      icon = Icons.cancel_rounded;
      title = "Unavailable";
    } else if (_responderStatus == "Dispatched") {
      startColor = const Color(0xFF1565C0);
      endColor = const Color(0xFF64B5F6);
      icon = Icons.local_fire_department;
      title = "Dispatched";
    } else {
      startColor = Colors.grey.shade700;
      endColor = Colors.blueGrey.shade300;
      icon = Icons.help_outline_rounded;
      title = _responderStatus;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(26),
      onTap: _toggleResponderStatus,
      child: Container(
        height: 145,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [startColor, endColor],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: endColor.withOpacity(0.25),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const Spacer(),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "Tap to change",
              style: TextStyle(
                color: Colors.white.withOpacity(0.88),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recentIncidentCard(Map<String, dynamic> alert) {
    final address =
        alert['userAddress'] ??
        alert['alertLocation'] ??
        alert['location'] ??
        "Unknown Address";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE5E5EA),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFD1D1D6),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.local_fire_department,
              color: Color(0xFFB71C1C),
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              address,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF1C1C1E),
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: () {
              _openAlertViewModal(alert);
            },
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: const Color(0xFFD1D1D6),
              foregroundColor: const Color(0xFFB71C1C),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              "View",
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
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
    final snapshotUrl =
        alert['snapshotUrl'] ??
        alert['snapshotBase64'] ??
        alert['imageBase64'] ??
        alert['photo'];

    final userLat = (alert['userLatitude'] as num?)?.toDouble();
    final userLng = (alert['userLongitude'] as num?)?.toDouble();

    final type = alert['type'] ?? alert['alertType'] ?? 'Unknown';
    final location = alert['location'] ?? alert['alertLocation'] ?? 'Unknown';
    final reporter = alert['userName'] ?? alert['userReported'] ?? 'N/A';
    final contact = alert['userContact'] ?? 'N/A';
    final address = alert['userAddress'] ?? alert['alertLocation'] ?? 'N/A';

    String timestampText = "N/A";
    final ts = alert['timestamp'];
    if (ts is Timestamp) {
      final dt = ts.toDate();
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? "PM" : "AM";
      timestampText =
          "${_monthName(dt.month)} ${dt.day}, ${dt.year} • $hour:$minute $period";
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.82,
        minChildSize: 0.6,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF7F7FA),
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFE5E5),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.local_fire_department,
                        color: Color(0xFFB71C1C),
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        "Incident Details",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1C1C1E),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                      color: const Color(0xFF1C1C1E),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  children: [
                    if (snapshotUrl != null &&
                        snapshotUrl.toString().trim().isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: _buildSnapshotImage(snapshotUrl),
                      ),
                      const SizedBox(height: 18),
                    ],
                    _modernInfoCard(
                      icon: Icons.warning_amber_rounded,
                      label: "Type",
                      value: type.toString(),
                    ),
                    const SizedBox(height: 10),
                    _modernInfoCard(
                      icon: Icons.swap_horiz_rounded,
                      label: "Dispatch Type",
                      value:
                          (alert['dispatchType'] ??
                                  alert['dispatch_type'] ??
                                  alert['backupType'] ??
                                  alert['requestType'] ??
                                  'Primary')
                              .toString(),
                    ),
                    const SizedBox(height: 10),
                    const SizedBox(height: 10),
                    _modernInfoCard(
                      icon: Icons.person_rounded,
                      label: "Reporter",
                      value: reporter.toString(),
                    ),
                    const SizedBox(height: 10),
                    _modernInfoCard(
                      icon: Icons.phone_rounded,
                      label: "Contact",
                      value: contact.toString(),
                    ),
                    const SizedBox(height: 10),
                    _modernInfoCard(
                      icon: Icons.home_rounded,
                      label: "Address",
                      value: address.toString(),
                    ),
                    const SizedBox(height: 10),
                    _modernInfoCard(
                      icon: Icons.access_time_rounded,
                      label: "Timestamp",
                      value: timestampText,
                    ),
                    if (userLat != null && userLng != null) ...[
                      const SizedBox(height: 10),
                      _modernInfoCard(
                        icon: Icons.location_searching_rounded,
                        label: "Coordinates",
                        value: "$userLat, $userLng",
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 10,
                      offset: Offset(0, -2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    if (userLat != null && userLng != null)
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            Navigator.pop(context);
                            await _openNavigationToAlert(
                              alertLat: userLat,
                              alertLng: userLng,
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            elevation: 0,
                            backgroundColor: const Color(0xFFB71C1C),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          icon: const Icon(Icons.navigation_rounded),
                          label: const Text(
                            "Navigate",
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    if (userLat != null && userLng != null)
                      const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          elevation: 0,
                          backgroundColor: const Color(0xFFE5E5EA),
                          foregroundColor: const Color(0xFF1C1C1E),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          "Close",
                          style: TextStyle(fontWeight: FontWeight.w600),
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

  Widget _buildDispatchStatusCard() {
    Color startColor, endColor;
    IconData icon;

    if (_dispatchStatus == "Dispatched") {
      startColor = const Color(0xFFFF4B3E);
      endColor = const Color(0xFFFFA000);
      icon = Icons.local_fire_department;
    } else if (_dispatchStatus == "Resolved") {
      startColor = const Color(0xFF43A047);
      endColor = const Color(0xFF00A896);
      icon = Icons.check_circle;
    } else {
      startColor = Colors.grey;
      endColor = Colors.blueGrey;
      icon = Icons.lock_outline;
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [startColor, endColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: endColor.withOpacity(0.22),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 32),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _dispatchStatus == "Dispatched"
                          ? "Team $_teamName is dispatched"
                          : _dispatchStatus,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_dispatchStatus == "Dispatched") ...[
                      Text(
                        "Type: ${_currentAlertType ?? 'Unknown'}",
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.95),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    if (_callerAddress.isNotEmpty) ...[
                      Text(
                        "Address: $_callerAddress",
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.95),
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    if (_currentDispatchTimestampText.isNotEmpty)
                      Text(
                        "Timestamp: $_currentDispatchTimestampText",
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.95),
                          fontSize: 14,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),

          if (_dispatchStatus == "Dispatched") ...[
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: SizedBox(
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: () {
                    _stopAlarm();
                    _openAlertDetails();
                  },
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: Colors.white.withOpacity(0.18),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  icon: const Icon(Icons.visibility_rounded, size: 18),
                  label: const Text(
                    "View",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 14),

            Center(
              child: GestureDetector(
                onTap:
                    (!_isTeamLeader ||
                        _hasPendingBackupRequest ||
                        _isRequestingBackup)
                    ? null
                    : _requestBackup,
                child: Opacity(
                  opacity:
                      (!_isTeamLeader ||
                          _hasPendingBackupRequest ||
                          _isRequestingBackup)
                      ? 0.55
                      : 1,
                  child: Container(
                    width: 170,
                    height: 170,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFFFEBEE),
                    ),
                    child: Center(
                      child: Container(
                        width: 130,
                        height: 130,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFFFCDD2),
                        ),
                        child: Center(
                          child: Container(
                            width: 98,
                            height: 98,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFF4D5A), Color(0xFFFF5F6D)],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFFFF5F6D,
                                  ).withOpacity(0.35),
                                  blurRadius: 16,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Center(
                              child: _isRequestingBackup
                                  ? const SizedBox(
                                      width: 26,
                                      height: 26,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.4,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      child: Text(
                                        _hasPendingBackupRequest
                                            ? "Requested"
                                            : "Request\nBackup",
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          height: 1.1,
                                          shadows: [
                                            Shadow(
                                              color: Colors.black26,
                                              blurRadius: 4,
                                              offset: Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 14),

            SizedBox(
              width: double.infinity,
              child: SizedBox(
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: _isTeamLeader ? _markAsResolved : null,
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.white.withOpacity(0.12),
                    disabledForegroundColor: Colors.white54,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: const Text(
                    "Resolve",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openAlertDetails() async {
    if (_currentAlertId == null) return;

    final snap = await FirebaseFirestore.instance
        .collection("alerts")
        .doc(_currentAlertId)
        .get();

    if (!snap.exists) return;

    final data = snap.data();
    if (data == null) return;

    if (!mounted) return;
    _openAlertViewModal(data);
  }

  void _markAsResolved() async {
    if (!_isTeamLeader) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Only the team leader can resolve the incident."),
        ),
      );
      return;
    }

    if (_currentDispatchId == null) return;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "Confirm Resolve",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          "Are you sure you want to mark this incident as resolved?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text("Resolve"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final currentDispatch = await FirebaseFirestore.instance
          .collection('dispatches')
          .doc(_currentDispatchId)
          .get();

      if (!currentDispatch.exists) return;

      final currentData = currentDispatch.data() as Map<String, dynamic>;
      final alertId = currentData["alertId"];

      if (alertId == null) return;

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

        batch.update(doc.reference, {'status': 'Resolved'});

        final responders = (data["responders"] as List<dynamic>? ?? []);
        for (final r in responders) {
          if (r is Map) {
            if (r["id"] != null) {
              responderIds.add(r["id"].toString());
            }
            if (r["teamId"] != null) {
              teamIds.add(r["teamId"].toString());
            }
            if (r["team"] != null) {
              teamNames.add(r["team"].toString());
            } else if (r["teamName"] != null) {
              teamNames.add(r["teamName"].toString());
            }
          }
        }

        final members = (data["members"] as List<dynamic>? ?? []);
        for (final m in members) {
          if (m is Map) {
            if (m["id"] != null) {
              responderIds.add(m["id"].toString());
            }
            if (m["teamId"] != null) {
              teamIds.add(m["teamId"].toString());
            }
            if (m["teamName"] != null) {
              teamNames.add(m["teamName"].toString());
            }
          }
        }
      }

      batch.update(
        FirebaseFirestore.instance.collection('alerts').doc(alertId),
        {'status': 'Resolved'},
      );

      for (final id in responderIds) {
        batch.update(FirebaseFirestore.instance.collection('users').doc(id), {
          'status': 'Available',
        });
      }

      for (final id in teamIds) {
        batch.update(FirebaseFirestore.instance.collection('teams').doc(id), {
          'status': 'Available',
        });
      }

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
        _isTeamLeader = false;
        _currentAlertType = null;
        _currentDispatchTimestampText = "";
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Incident resolved. All teams cleared.")),
      );
    } catch (e) {
      debugPrint("Resolve error: $e");

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to resolve incident: $e")));
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

  Future<void> _openNavigationToAlert({
    required double alertLat,
    required double alertLng,
    String? alertAddress,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // ✅ Get logged-in responder
      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: user.email)
          .limit(1)
          .get();

      if (userSnap.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Responder record not found.")),
        );
        return;
      }

      final userDoc = userSnap.docs.first.data() as Map<String, dynamic>;
      final stationId = userDoc['stationId']?.toString();

      if (stationId == null || stationId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Responder station not assigned.")),
        );
        return;
      }

      // ✅ Get actual station document
      final stationSnap = await FirebaseFirestore.instance
          .collection('stations')
          .doc(stationId)
          .get();

      if (!stationSnap.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Station record not found.")),
        );
        return;
      }

      final stationDoc = stationSnap.data() as Map<String, dynamic>;

      final stationLat = (stationDoc['latitude'] as num?)?.toDouble();
      final stationLng = (stationDoc['longitude'] as num?)?.toDouble();
      final stationAddress =
          stationDoc['address']?.toString() ?? "No station address";
      final stationName = stationDoc['name']?.toString() ?? "Station";

      if (stationLat == null || stationLng == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Station coordinates missing.")),
        );
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MapNavigationPage(
            stationLat: stationLat,
            stationLng: stationLng,
            stationAddress: stationAddress,
            stationName: stationName,
            alertLat: alertLat,
            alertLng: alertLng,
            alertAddress: alertAddress,
            apiKey: "AIzaSyC4Ai-W_V2M7qftiuQBYcnyCL8oqaDF680", // ✅ make sure apiKey exists in your class
          ),
        ),
      );
    } catch (e) {
      debugPrint("Navigation error: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Navigation error: $e")));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Could not open maps.")));
    }
  }
}
