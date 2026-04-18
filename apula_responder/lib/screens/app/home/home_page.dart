// lib/screens/app/home/home_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

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
import 'package:lottie/lottie.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

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

  bool _validatePressed = false;

  bool _isPageLoading = true;

  String _dispatchStatus = "Loading...";
  StreamSubscription? _dispatchSub;
  String _callerAddress = "";

  List<Map<String, dynamic>> _recentAlerts = [];

  String _responderStatus = "Available";

  final AudioPlayer _player = AudioPlayer();
  bool _hasPlayedSound = false;
  int _unreadNotifCount = 0;

  String? _currentDispatchId;
  String? _currentAlertId;

  bool _isTeamLeader = false;

  String _userName = "Responder";
  String _teamName = "No Team";
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();
  final ScrollController _dashboardScrollController = ScrollController();

  String? _teamId;
  String? _stationName;
  String? _vehicleCode;
  String? _vehiclePlateNumber;
  String? _leaderName;
  List<String> _teamMembers = [];

  double? _currentTemp;
  String _weatherTitle = "Loading...";
  String _weatherLocation = "Getting location...";
  bool _weatherLoading = true;
  int? _weatherCode;

  String? _currentAlertType;
  String _currentDispatchTimestampText = "";
  String _currentValidatedTimestampText = "";
  String _currentConfirmedTimestampText = "";

  final GlobalKey _weatherCardKey = GlobalKey();
  final GlobalKey _responderInfoKey = GlobalKey();
  final GlobalKey _availabilityKey = GlobalKey();
  final GlobalKey _dispatchStatusKey = GlobalKey();

  final GlobalKey _navHomeKey = GlobalKey();
  final GlobalKey _navDispatchKey = GlobalKey();
  final GlobalKey _navNotificationsKey = GlobalKey();
  final GlobalKey _navSettingsKey = GlobalKey();

  TutorialCoachMark? _tutorialCoachMark;
  bool _tutorialShownThisSession = false;
  bool _isShowingOnboarding = false;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showInitialLoading();
    });

    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());

    _listenToDispatchStatus();
    _loadRecentAlerts();
    _getResponderStatus();
    _listenUnreadNotifications();
    _initializeLocalNotifications();
    _loadWeatherCardData();
  }

  Future<void> _maybeShowOnboardingTutorial() async {
    if (!mounted || _tutorialShownThisSession || _isShowingOnboarding) return;
    if (_selectedIndex != 0) return;

    final prefs = await SharedPreferences.getInstance();
    final hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;

    if (hasSeenOnboarding) return;

    _tutorialShownThisSession = true;
    _isShowingOnboarding = true;

    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;

    _showOnboardingIntro();
  }

  void _showOnboardingDoneDialog() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF2E7D32),
                  size: 42,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                "You're All Set",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF1C1C1E),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "You have completed the responder onboarding guide. You can now use the dashboard and response tools with confidence.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF636366),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: const Color(0xFFB71C1C),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text("Continue"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showOnboardingIntro() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(
                  Icons.local_fire_department_rounded,
                  color: Color(0xFFB71C1C),
                  size: 42,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                "Welcome to APULA Responder",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF1C1C1E),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "This quick walkthrough will guide you through the dashboard, responder tools, and key actions needed during emergency response.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF636366),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7FA),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Guide Coverage",
                      style: TextStyle(
                        color: Color(0xFFB71C1C),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text("• Dashboard overview"),
                    Text("• Responder and team details"),
                    Text("• Availability status"),
                    Text("• Dispatch monitoring"),
                    Text("• Navigation shortcuts"),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('has_seen_onboarding', true);
                        if (!mounted) return;
                        Navigator.pop(context);
                        _isShowingOnboarding = false;
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFB71C1C),
                        side: const BorderSide(color: Color(0xFFB71C1C)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text("Skip"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        await Future.delayed(const Duration(milliseconds: 300));
                        if (!mounted) return;
                        _showOnboardingTutorial();
                      },
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: const Color(0xFFB71C1C),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text("Start Guide"),
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

  Future<void> _showInitialLoading() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _loadingDialog("Loading dashboard..."),
    );

    await Future.wait([
      _getResponderStatus(),
      _loadRecentAlerts(),
      _loadWeatherCardData(),
    ]);

    if (mounted) {
      Navigator.pop(context);
      setState(() => _isPageLoading = false);
      await _maybeShowOnboardingTutorial();
    }
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

  Widget _loadingDialog(String msg) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Lottie.asset('assets/fireloading.json', width: 130, height: 130),
          const SizedBox(height: 20),
          Text(
            msg,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFB71C1C),
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  void _showOnboardingTutorial() {
    const totalSteps = 8;

    final targets = <TargetFocus>[
      TargetFocus(
        identify: "weather_card",
        keyTarget: _weatherCardKey,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            child: _tutorialContent(
              step: 1,
              total: totalSteps,
              title: "Dashboard Overview",
              description: "View weather, time, and location here.",
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: "responder_info",
        keyTarget: _responderInfoKey,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            child: _tutorialContent(
              step: 2,
              total: totalSteps,
              title: "Responder Info",
              description: "Shows your team and identity.",
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: "availability",
        keyTarget: _availabilityKey,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            child: _tutorialContent(
              step: 3,
              total: totalSteps,
              title: "Status",
              description: "Tap to change availability.",
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: "dispatch_status",
        keyTarget: _dispatchStatusKey,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            child: _tutorialContent(
              step: 4,
              total: totalSteps,
              title: "Dispatch",
              description: "Shows active emergency status.",
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: "nav_home",
        keyTarget: _navHomeKey,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            child: _tutorialContent(
              step: 5,
              total: totalSteps,
              title: "Home",
              description: "Return to dashboard.",
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: "nav_dispatch",
        keyTarget: _navDispatchKey,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            child: _tutorialContent(
              step: 6,
              total: totalSteps,
              title: "Dispatch Page",
              description: "View dispatch records.",
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: "nav_notifications",
        keyTarget: _navNotificationsKey,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            child: _tutorialContent(
              step: 7,
              total: totalSteps,
              title: "Notifications",
              description: "View alerts.",
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: "nav_settings",
        keyTarget: _navSettingsKey,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            child: _tutorialContent(
              step: 8,
              total: totalSteps,
              title: "Settings",
              description: "Manage account.",
            ),
          ),
        ],
      ),
    ];

    _tutorialCoachMark = TutorialCoachMark(
      targets: targets,
      textSkip: "Skip",
      onFinish: () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('has_seen_onboarding', true);
        _isShowingOnboarding = false;
      },
      onSkip: () {
        SharedPreferences.getInstance().then((prefs) {
          prefs.setBool('has_seen_onboarding', true);
        });

        _isShowingOnboarding = false;
        return true;
      },
    );

    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;

      if (_weatherCardKey.currentContext == null) {
        debugPrint("Targets not ready");
        return;
      }

      _dashboardScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );

      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        _tutorialCoachMark?.show(context: context);
      });
    });
  }

  Widget _tutorialContent({
    required int step,
    required int total,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Step $step of $total",
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(description),
          const SizedBox(height: 10),
          const Text("Tap anywhere to continue"),
        ],
      ),
    );
  }

  String _formatTimestamp(dynamic ts) {
    if (ts is! Timestamp) return "";

    final dt = ts.toDate();
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? "PM" : "AM";

    return "${_monthName(dt.month)} ${dt.day}, ${dt.year} $hour:$minute $period";
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
        final rawTeamName = (data['teamName'] ?? '').toString().trim();
        final normalizedTeamName =
            rawTeamName.isEmpty || rawTeamName.toLowerCase() == "no team"
            ? "Unassigned"
            : rawTeamName;

        final resolvedTeamId = (data['teamId'] ?? '').toString().trim();
        final resolvedVehicleCode = (data['vehicleCode'] ?? '')
            .toString()
            .trim();

        if (!mounted) return;
        setState(() {
          _responderStatus = data['status'] ?? "Available";
          _userName = data['name'] ?? "Responder";
          _teamName = normalizedTeamName;
          _teamId = resolvedTeamId.isEmpty ? null : resolvedTeamId;
          _stationName = (data['stationName'] ?? '').toString().trim().isEmpty
              ? null
              : data['stationName'].toString();
          _vehicleCode = resolvedVehicleCode.isEmpty
              ? null
              : resolvedVehicleCode;
        });

        // FIX:
        // load team/truck info if either teamId OR a real teamName exists
        if ((_teamId != null && _teamId!.isNotEmpty) ||
            (_teamName.trim().isNotEmpty && _teamName != "Unassigned")) {
          await _loadTeamTruckInfo();
        } else {
          if (!mounted) return;
          setState(() {
            _vehiclePlateNumber = null;
            _leaderName = null;
            _teamMembers = [];
          });
        }
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
            _dispatchStatus = "No Active Dispatch";
            _callerAddress = "";
            _currentDispatchId = null;
            _currentAlertId = null;
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

        final String dispatchTimestampText = _formatTimestamp(
          data["dispatchedAt"] ?? data["timestamp"],
        );

        final String validatedTimestampText = _formatTimestamp(
          data["validatedAt"],
        );

        final String confirmedTimestampText = _formatTimestamp(
          data["confirmedAt"],
        );

        final bool leader = await _resolveLeaderForDispatch(docSnap.id, data);

        if (!mounted) return;
        setState(() {
          _dispatchStatus = status;
          _callerAddress = address;
          _currentDispatchId = docSnap.id;
          _currentAlertId = data["alertId"];
          _isTeamLeader = leader;
          _currentAlertType = alertType.toString();
          _currentDispatchTimestampText = dispatchTimestampText;
          _currentValidatedTimestampText = validatedTimestampText;
          _currentConfirmedTimestampText = confirmedTimestampText;
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

          if (_responderStatus != "Dispatched") {
            await _updateUserStatus("Dispatched");
          }
        }

        if (status == "Validated") {
          _hasPlayedSound = false;

          if (_responderStatus != "Unavailable") {
            await _updateUserStatus("Available");
          }

          if (!mounted) return;
          setState(() {
            _dispatchStatus = "Validated";
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

  Future<void> _refreshDashboard() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _loadingDialog("Refreshing data..."),
    );

    await Future.wait([
      _getResponderStatus(),
      _loadRecentAlerts(),
      _loadWeatherCardData(),
    ]);

    _listenToDispatchStatus();

    if (mounted) Navigator.pop(context);
  }

  Future<void> _loadTeamTruckInfo() async {
    try {
      String? resolvedTeamId = _teamId;
      String? resolvedTeamName = _teamName == "Unassigned"
          ? null
          : _teamName.trim();

      DocumentSnapshot<Map<String, dynamic>>? teamDoc;

      // 1. Try by teamId first
      if (resolvedTeamId != null && resolvedTeamId.isNotEmpty) {
        final doc = await FirebaseFirestore.instance
            .collection('teams')
            .doc(resolvedTeamId)
            .get();

        if (doc.exists) {
          teamDoc = doc;
        }
      }

      // 2. Fallback by teamName
      if (teamDoc == null &&
          resolvedTeamName != null &&
          resolvedTeamName.isNotEmpty) {
        final snap = await FirebaseFirestore.instance
            .collection('teams')
            .where('teamName', isEqualTo: resolvedTeamName)
            .limit(1)
            .get();

        if (snap.docs.isNotEmpty) {
          teamDoc = snap.docs.first;
        }
      }

      if (teamDoc == null || !teamDoc.exists) {
        if (!mounted) return;
        setState(() {
          _leaderName = null;
          _teamMembers = [];
          _vehiclePlateNumber = null;
        });
        return;
      }

      final teamData = teamDoc.data() as Map<String, dynamic>;

      // keep team id/name synced from actual team doc
      resolvedTeamId = teamDoc.id;
      resolvedTeamName = (teamData['teamName'] ?? resolvedTeamName ?? '')
          .toString()
          .trim();

      final teamMembersRaw = teamData['members'];
      final leaderId = (teamData['leaderId'] ?? '').toString().trim();

      String? foundLeaderName;
      final Set<String> uniqueMembers = {};
      final List<String> members = [];

      if (teamMembersRaw is List) {
        for (final item in teamMembersRaw) {
          if (item is Map) {
            final name = (item['name'] ?? 'Unknown').toString().trim();
            final memberId = (item['id'] ?? '').toString().trim();

            if (name.isNotEmpty && !uniqueMembers.contains(name)) {
              uniqueMembers.add(name);
              members.add(name);
            }

            if (memberId == leaderId && name.isNotEmpty) {
              foundLeaderName = name;
            }
          }
        }
      }

      foundLeaderName ??=
          (teamData['leaderName'] ?? '').toString().trim().isEmpty
          ? null
          : teamData['leaderName'].toString().trim();

      String? plateNumber;
      String? vehicleCode = _vehicleCode?.trim();
      String? vehicleId =
          (teamData['vehicleId'] ?? '').toString().trim().isEmpty
          ? null
          : teamData['vehicleId'].toString().trim();

      // team vehicleCode fallback
      if ((vehicleCode == null || vehicleCode.isEmpty) &&
          teamData['vehicleCode'] != null) {
        final teamVehicleCode = teamData['vehicleCode'].toString().trim();
        if (teamVehicleCode.isNotEmpty) {
          vehicleCode = teamVehicleCode;
        }
      }

      DocumentSnapshot<Map<String, dynamic>>? matchedVehicleDoc;

      // 3. Try direct vehicleId from team
      if (vehicleId != null && vehicleId.isNotEmpty) {
        final vehicleDoc = await FirebaseFirestore.instance
            .collection('vehicles')
            .doc(vehicleId)
            .get();

        if (vehicleDoc.exists) {
          matchedVehicleDoc = vehicleDoc;
        }
      }

      // 4. Try by vehicle code
      if (matchedVehicleDoc == null &&
          vehicleCode != null &&
          vehicleCode.isNotEmpty) {
        final vehicleSnap = await FirebaseFirestore.instance
            .collection('vehicles')
            .where('code', isEqualTo: vehicleCode)
            .limit(1)
            .get();

        if (vehicleSnap.docs.isNotEmpty) {
          matchedVehicleDoc = vehicleSnap.docs.first;
        }
      }

      // 5. NEW FIX:
      // Try by assignedTeamId if team doc/user doc does not store vehicleId
      if (matchedVehicleDoc == null &&
          resolvedTeamId != null &&
          resolvedTeamId.isNotEmpty) {
        final vehicleSnap = await FirebaseFirestore.instance
            .collection('vehicles')
            .where('assignedTeamId', isEqualTo: resolvedTeamId)
            .limit(1)
            .get();

        if (vehicleSnap.docs.isNotEmpty) {
          matchedVehicleDoc = vehicleSnap.docs.first;
        }
      }

      // 6. NEW FIX:
      // Fallback by assignedTeam name
      if (matchedVehicleDoc == null &&
          resolvedTeamName != null &&
          resolvedTeamName.isNotEmpty) {
        final vehicleSnap = await FirebaseFirestore.instance
            .collection('vehicles')
            .where('assignedTeam', isEqualTo: resolvedTeamName)
            .limit(1)
            .get();

        if (vehicleSnap.docs.isNotEmpty) {
          matchedVehicleDoc = vehicleSnap.docs.first;
        }
      }

      // 7. Extract vehicle details
      if (matchedVehicleDoc != null && matchedVehicleDoc.exists) {
        final vehicleData = matchedVehicleDoc.data() as Map<String, dynamic>;

        final plate =
            (vehicleData['plateNumber'] ??
                    vehicleData['plateNo'] ??
                    vehicleData['plate'] ??
                    '')
                .toString()
                .trim();

        if (plate.isNotEmpty) {
          plateNumber = plate;
        }

        if (vehicleCode == null || vehicleCode.isEmpty) {
          final vCode =
              (vehicleData['code'] ?? vehicleData['vehicleCode'] ?? '')
                  .toString()
                  .trim();
          if (vCode.isNotEmpty) {
            vehicleCode = vCode;
          }
        }

        vehicleId ??= matchedVehicleDoc.id;
      }

      if (!mounted) return;
      setState(() {
        _teamId = resolvedTeamId;
        if (resolvedTeamName != null && resolvedTeamName.isNotEmpty) {
          _teamName = resolvedTeamName!;
        }
        _leaderName = foundLeaderName;
        _teamMembers = members;
        _vehicleCode = (vehicleCode != null && vehicleCode.isNotEmpty)
            ? vehicleCode
            : null;
        _vehiclePlateNumber = (plateNumber != null && plateNumber.isNotEmpty)
            ? plateNumber
            : null;
      });

      debugPrint("TEAM INFO LOADED");
      debugPrint("teamId: $_teamId");
      debugPrint("teamName: $_teamName");
      debugPrint("leaderName: $_leaderName");
      debugPrint("vehicleCode: $_vehicleCode");
      debugPrint("vehiclePlateNumber: $_vehiclePlateNumber");
      debugPrint("teamMembers: $_teamMembers");
    } catch (e) {
      debugPrint("Load team truck info error: $e");
    }
  }

  void _showTeamTruckInfoModal() {
    final displayTeam =
        _teamName.trim().isEmpty || _teamName.trim().toLowerCase() == "no team"
        ? "Unassigned"
        : _teamName;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        decoration: const BoxDecoration(
          color: Color(0xFFF7F7FA),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 46,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Center(
                  child: Text(
                    "Team & Truck Information",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFB71C1C),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _modernInfoCard(
                  icon: Icons.groups_rounded,
                  label: "Team",
                  value: displayTeam == "Unassigned"
                      ? "Team Unassigned"
                      : "Team $displayTeam",
                ),
                const SizedBox(height: 12),
                _modernInfoCard(
                  icon: Icons.local_shipping_rounded,
                  label: "Truck Code",
                  value: (_vehicleCode == null || _vehicleCode!.trim().isEmpty)
                      ? "No truck assigned"
                      : _vehicleCode!,
                ),
                const SizedBox(height: 12),
                _modernInfoCard(
                  icon: Icons.pin_outlined,
                  label: "Truck Plate Number",
                  value:
                      (_vehiclePlateNumber == null ||
                          _vehiclePlateNumber!.trim().isEmpty)
                      ? "No plate number available"
                      : _vehiclePlateNumber!,
                ),
                const SizedBox(height: 12),
                _modernInfoCard(
                  icon: Icons.person_rounded,
                  label: "Leader",
                  value: (_leaderName == null || _leaderName!.trim().isEmpty)
                      ? "No leader assigned"
                      : _leaderName!,
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.badge_rounded, color: Color(0xFFB71C1C)),
                          SizedBox(width: 8),
                          Text(
                            "Members",
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1C1C1E),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_teamMembers.isEmpty)
                        const Text(
                          "No members available.",
                          style: TextStyle(
                            color: Color(0xFF636366),
                            fontSize: 14,
                          ),
                        )
                      else
                        ..._teamMembers.map(
                          (member) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.circle,
                                  size: 8,
                                  color: Color(0xFFB71C1C),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    member,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF1C1C1E),
                                      fontWeight: FontWeight.w500,
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
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: const Color(0xFFB71C1C),
                      foregroundColor: Colors.white,
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
        ),
      ),
    );
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
    _dashboardScrollController.dispose();
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

      final rawTeamName = (data['teamName'] ?? '').toString().trim();
      final normalizedTeamName =
          rawTeamName.isEmpty || rawTeamName.toLowerCase() == "no team"
          ? "Unassigned"
          : rawTeamName;

      final resolvedTeamId = (data['teamId'] ?? '').toString().trim();
      final resolvedVehicleCode = (data['vehicleCode'] ?? '').toString().trim();

      if (!mounted) return;
      setState(() {
        _responderStatus = newStatus;
        _userName = data['name'] ?? _userName;
        _teamName = normalizedTeamName;
        _teamId = resolvedTeamId.isEmpty ? null : resolvedTeamId;
        _stationName = (data['stationName'] ?? '').toString().trim().isEmpty
            ? null
            : data['stationName'].toString();
        _vehicleCode = resolvedVehicleCode.isEmpty ? null : resolvedVehicleCode;
      });

      // FIX:
      // load team/truck info if either teamId OR a real teamName exists
      if ((_teamId != null && _teamId!.isNotEmpty) ||
          (_teamName.trim().isNotEmpty && _teamName != "Unassigned")) {
        await _loadTeamTruckInfo();
      } else {
        if (!mounted) return;
        setState(() {
          _vehiclePlateNumber = null;
          _leaderName = null;
          _teamMembers = [];
        });
      }
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
        homeKey: _navHomeKey,
        dispatchKey: _navDispatchKey,
        notificationsKey: _navNotificationsKey,
        settingsKey: _navSettingsKey,
      ),
    );
  }

  Widget _buildDashboard(BuildContext context) {
    return RefreshIndicator(
      key: _refreshIndicatorKey,
      onRefresh: _refreshDashboard,
      color: const Color(0xFFB71C1C),
      child: SingleChildScrollView(
        controller: _dashboardScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Ready to Respond",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Container(key: _weatherCardKey, child: _buildTimeCard()),
            const SizedBox(height: 16),
            Container(
              key: _dispatchStatusKey,
              child: _buildDispatchStatusCard(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Container(
                    key: _responderInfoKey,
                    child: _buildResponderInfoCard(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    key: _availabilityKey,
                    child: _buildStatusCard(),
                  ),
                ),
              ],
            ),
          ],
        ),
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

    final String displayTeam =
        _teamName.trim().isEmpty || _teamName.trim().toLowerCase() == "no team"
        ? "Unassigned"
        : _teamName;

    return InkWell(
      borderRadius: BorderRadius.circular(26),
      onTap: _showTeamTruckInfoModal,
      child: Container(
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
              "Team $displayTeam",
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

  void _stopAlarm() {
    try {
      _player.stop();
    } catch (_) {}

    _hasPlayedSound = true;
  }

  Future<String?> _pickValidationImageBase64(ImageSource source) async {
    try {
      final XFile? file = await _imagePicker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1280,
      );

      if (file == null) return null;

      final bytes = await File(file.path).readAsBytes();
      return base64Encode(bytes);
    } catch (e) {
      debugPrint("Validation image pick error: $e");
      return null;
    }
  }

  Future<void> _saveValidationReport({
    required String dispatchId,
    required String alertId,
    required List<String> fireTypes,
    required String sourceOfFire,
    required bool injuredOrTrapped,
    required List<String> resourcesNeeded,
    required String remarks,
    required bool skippedBecauseRadioed,
    String? actualFireImageBase64,
  }) async {
    final currentUser = await _getCurrentUserData();
    if (currentUser == null) return;

    final userName = (currentUser['name'] ?? 'Responder').toString();
    final userEmail = (currentUser['email'] ?? '').toString().toLowerCase();
    final userId = (currentUser['docId'] ?? '').toString();

    final report = <String, dynamic>{
      'fireTypes': fireTypes,
      'sourceOfFire': sourceOfFire.trim(),
      'injuredOrTrapped': injuredOrTrapped,
      'resourcesNeeded': resourcesNeeded,
      'remarks': remarks.trim(),
      'skippedBecauseRadioed': skippedBecauseRadioed,
      'validatedBy': userName,
      'validatedByEmail': userEmail,
      'validatedById': userId,
      'submittedAt': FieldValue.serverTimestamp(),
    };

    if (actualFireImageBase64 != null &&
        actualFireImageBase64.trim().isNotEmpty) {
      report['actualFireImageBase64'] = actualFireImageBase64.trim();
    }

    await FirebaseFirestore.instance
        .collection('dispatches')
        .doc(dispatchId)
        .update({
          'validationReport': report,
          'validationFormSubmittedAt': FieldValue.serverTimestamp(),
        });

    await FirebaseFirestore.instance.collection('alerts').doc(alertId).set({
      'latestValidationReport': report,
      'latestValidationDispatchId': dispatchId,
      'latestValidationSubmittedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _openValidationFormPage() async {
    if (_currentDispatchId == null || _currentAlertId == null) return;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ValidationFormPage(
          onPickImageBase64: _pickValidationImageBase64,
          onSubmit:
              ({
                required List<String> fireTypes,
                required String sourceOfFire,
                required bool injuredOrTrapped,
                required List<String> resourcesNeeded,
                required String remarks,
                required bool skippedBecauseRadioed,
                String? actualFireImageBase64,
              }) async {
                await _saveValidationReport(
                  dispatchId: _currentDispatchId!,
                  alertId: _currentAlertId!,
                  fireTypes: fireTypes,
                  sourceOfFire: sourceOfFire,
                  injuredOrTrapped: injuredOrTrapped,
                  resourcesNeeded: resourcesNeeded,
                  remarks: remarks,
                  skippedBecauseRadioed: skippedBecauseRadioed,
                  actualFireImageBase64: actualFireImageBase64,
                );
              },
        ),
      ),
    );

    if (result == true) {
      await _validateIncident();
    }
  }

  void _openAlertViewModal(Map<String, dynamic> alert) {
    final List<dynamic> imageCandidates = [
      alert['snapshotUrl'],
      alert['snapshotBase64'],
      alert['snapshot'],
      alert['imageUrl'],
      alert['image'],
      alert['imageBase64'],
      alert['photo'],
      alert['photoUrl'],
    ];

    dynamic snapshotSource;
    for (final candidate in imageCandidates) {
      if (candidate != null && candidate.toString().trim().isNotEmpty) {
        snapshotSource = candidate;
        break;
      }
    }

    final userLat =
        (alert['userLatitude'] as num?)?.toDouble() ??
        (alert['latitude'] as num?)?.toDouble() ??
        (alert['lat'] as num?)?.toDouble();

    final userLng =
        (alert['userLongitude'] as num?)?.toDouble() ??
        (alert['longitude'] as num?)?.toDouble() ??
        (alert['lng'] as num?)?.toDouble();

    final type = alert['type'] ?? alert['alertType'] ?? 'Unknown';
    final reporter = alert['userName'] ?? alert['userReported'] ?? 'N/A';
    final contact = alert['userContact'] ?? 'N/A';
    final address =
        alert['userAddress'] ??
        alert['alertLocation'] ??
        alert['location'] ??
        'N/A';

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
                    ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child:
                          (snapshotSource != null &&
                              snapshotSource.toString().trim().isNotEmpty)
                          ? _buildSnapshotImage(snapshotSource)
                          : Container(
                              height: 210,
                              width: double.infinity,
                              color: Colors.black12,
                              child: const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.image_not_supported_rounded,
                                      size: 40,
                                      color: Colors.black54,
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      "No fire image available",
                                      style: TextStyle(
                                        color: Colors.black54,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(height: 18),
                    _modernInfoCard(
                      icon: Icons.warning_amber_rounded,
                      label: "Type",
                      value: type.toString(),
                    ),
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
                      label: "Fire Address",
                      value: address.toString(),
                    ),
                    const SizedBox(height: 10),
                    _modernInfoCard(
                      icon: Icons.access_time_rounded,
                      label: "Time",
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
              SafeArea(
                top: false,
                child: Container(
                  padding: EdgeInsets.fromLTRB(20, 14, 20, 8),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
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
                              padding: const EdgeInsets.symmetric(vertical: 14),
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
                        )
                      else
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              elevation: 0,
                              backgroundColor: const Color(0xFFB71C1C),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDispatchStatusCard() {
    final bool isDispatched = _dispatchStatus == "Dispatched";
    final bool isValidated = _dispatchStatus == "Validated";
    final bool isAdminConfirmed = _dispatchStatus == "Confirmed";
    final bool noActiveDispatch = _dispatchStatus == "No Active Dispatch";

    Color topColor;
    Color bottomColor;
    IconData statusIcon;
    String title;
    String subtitle;

    if (isDispatched) {
      topColor = const Color(0xFFBF360C);
      bottomColor = const Color(0xFFFFA000);
      statusIcon = Icons.local_fire_department_rounded;
      title = "Active Dispatch";
      subtitle = "Immediate response required";
    } else if (isAdminConfirmed) {
      topColor = const Color(0xFF2E7D32);
      bottomColor = const Color(0xFF43A047);
      statusIcon = Icons.verified_user_rounded;
      title = "Confirmed";
      subtitle = "Incident officially confirmed";
    } else if (isValidated) {
      topColor = const Color(0xFF1565C0);
      bottomColor = const Color(0xFF1E88E5);
      statusIcon = Icons.verified_rounded;
      title = "Incident Validated";
      subtitle = "Dispatch completed successfully";
    } else {
      topColor = const Color(0xFF607D8B);
      bottomColor = const Color(0xFF90A4AE);
      statusIcon = Icons.shield_outlined;
      title = "No Active Dispatch";
      subtitle = "Waiting for incoming incident";
    }

    Widget detailTile({
      required IconData icon,
      required String label,
      required String value,
    }) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.78),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [topColor, bottomColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: bottomColor.withOpacity(0.20),
            blurRadius: 22,
            offset: const Offset(0, 10),
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
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withOpacity(0.10)),
                ),
                child: Icon(statusIcon, color: Colors.white, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _dispatchStatus.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.9,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.88),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          Container(
            width: double.infinity,
            height: 1,
            color: Colors.white.withOpacity(0.12),
          ),

          const SizedBox(height: 20),

          if (isDispatched) ...[
            if (_currentDispatchTimestampText.isNotEmpty)
              detailTile(
                icon: Icons.access_time_rounded,
                label: "DISPATCH TIME",
                value: _currentDispatchTimestampText,
              ),

            const SizedBox(height: 22),

            // 🔥 VIEW DETAILS BUTTON
            Center(
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: () {
                    _stopAlarm();
                    _openAlertDetails();
                  },
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF8E1F1F),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: const Icon(Icons.visibility_rounded, size: 20),
                  label: const Text(
                    "View Details",
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 18),

            // 🔥 ORIGINAL VALIDATE BUTTON (UNCHANGED)
            Center(
              child: GestureDetector(
                onTapDown: (_) => setState(() => _validatePressed = true),
                onTapUp: (_) async {
                  setState(() => _validatePressed = false);
                  await Future.delayed(const Duration(milliseconds: 70));
                  _openValidationFormPage();
                },
                onTapCancel: () => setState(() => _validatePressed = false),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  width: _validatePressed ? 110 : 120,
                  height: _validatePressed ? 110 : 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.96),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.90),
                      width: 1.2,
                    ),
                    boxShadow: _validatePressed
                        ? [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.14),
                              blurRadius: 14,
                              offset: const Offset(0, 8),
                            ),
                          ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(7),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      curve: Curves.easeOut,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF43A047), Color(0xFF2E7D32)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.16),
                          width: 1,
                        ),
                        boxShadow: _validatePressed
                            ? [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.10),
                                  blurRadius: 3,
                                  offset: const Offset(0, 1),
                                ),
                              ]
                            : [
                                BoxShadow(
                                  color: const Color(
                                    0xFF1B5E20,
                                  ).withOpacity(0.22),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                                BoxShadow(
                                  color: Colors.white.withOpacity(0.10),
                                  blurRadius: 2,
                                  offset: const Offset(0, -1),
                                ),
                              ],
                      ),
                      child: const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            "VALIDATE",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.9,
                              height: 1.1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ] else if (isValidated) ...[
            if (_currentValidatedTimestampText.isNotEmpty)
              detailTile(
                icon: Icons.verified_rounded,
                label: "VALIDATED TIME",
                value: _currentValidatedTimestampText,
              ),
          ] else if (isAdminConfirmed) ...[
            if (_currentConfirmedTimestampText.isNotEmpty)
              detailTile(
                icon: Icons.verified_user_rounded,
                label: "CONFIRMED TIME",
                value: _currentConfirmedTimestampText,
              ),
          ] else if (noActiveDispatch) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.10),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                "No active dispatch.",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 14,
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

  Future<Map<String, dynamic>?> _getCurrentUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return null;

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: user.email)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;

    final data = Map<String, dynamic>.from(snap.docs.first.data());
    data['docId'] = snap.docs.first.id;
    return data;
  }

  Future<void> _finalizeAlertValidation(String alertId) async {
    final dispatches = await FirebaseFirestore.instance
        .collection('dispatches')
        .where('alertId', isEqualTo: alertId)
        .get();

    final batch = FirebaseFirestore.instance.batch();

    final Set<String> responderIds = {};
    final Set<String> teamIds = {};
    final Set<String> teamNames = {};
    final Set<String> vehicleIds = {};
    final Set<String> vehicleCodes = {};

    for (final doc in dispatches.docs) {
      final data = doc.data();

      batch.update(doc.reference, {
        'status': 'Validated',
        'validatedAt': FieldValue.serverTimestamp(),
      });

      if (data['teamId'] != null &&
          data['teamId'].toString().trim().isNotEmpty) {
        teamIds.add(data['teamId'].toString());
      }

      if (data['teamName'] != null &&
          data['teamName'].toString().trim().isNotEmpty) {
        teamNames.add(data['teamName'].toString());
      }

      if (data['vehicleId'] != null &&
          data['vehicleId'].toString().trim().isNotEmpty) {
        vehicleIds.add(data['vehicleId'].toString());
      }

      if (data['vehicleCode'] != null &&
          data['vehicleCode'].toString().trim().isNotEmpty) {
        vehicleCodes.add(data['vehicleCode'].toString());
      }

      final responders = (data["responders"] as List<dynamic>? ?? []);
      for (final r in responders) {
        if (r is Map) {
          if (r["id"] != null && r["id"].toString().trim().isNotEmpty) {
            responderIds.add(r["id"].toString());
          }
          if (r["teamId"] != null && r["teamId"].toString().trim().isNotEmpty) {
            teamIds.add(r["teamId"].toString());
          }
          if (r["team"] != null && r["team"].toString().trim().isNotEmpty) {
            teamNames.add(r["team"].toString());
          } else if (r["teamName"] != null &&
              r["teamName"].toString().trim().isNotEmpty) {
            teamNames.add(r["teamName"].toString());
          }
          if (r["vehicleId"] != null &&
              r["vehicleId"].toString().trim().isNotEmpty) {
            vehicleIds.add(r["vehicleId"].toString());
          }
          if (r["vehicleCode"] != null &&
              r["vehicleCode"].toString().trim().isNotEmpty) {
            vehicleCodes.add(r["vehicleCode"].toString());
          }
        }
      }

      final members = (data["members"] as List<dynamic>? ?? []);
      for (final m in members) {
        if (m is Map) {
          if (m["id"] != null && m["id"].toString().trim().isNotEmpty) {
            responderIds.add(m["id"].toString());
          }
          if (m["teamId"] != null && m["teamId"].toString().trim().isNotEmpty) {
            teamIds.add(m["teamId"].toString());
          }
          if (m["teamName"] != null &&
              m["teamName"].toString().trim().isNotEmpty) {
            teamNames.add(m["teamName"].toString());
          }
          if (m["vehicleId"] != null &&
              m["vehicleId"].toString().trim().isNotEmpty) {
            vehicleIds.add(m["vehicleId"].toString());
          }
          if (m["vehicleCode"] != null &&
              m["vehicleCode"].toString().trim().isNotEmpty) {
            vehicleCodes.add(m["vehicleCode"].toString());
          }
        }
      }
    }

    batch.update(FirebaseFirestore.instance.collection('alerts').doc(alertId), {
      'status': 'Validated',
      'validatedAt': FieldValue.serverTimestamp(),
    });

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

    for (final id in vehicleIds) {
      batch.update(FirebaseFirestore.instance.collection('vehicles').doc(id), {
        'status': 'Available',
      });
    }

    for (final code in vehicleCodes) {
      final vehicleSnap = await FirebaseFirestore.instance
          .collection('vehicles')
          .where('code', isEqualTo: code)
          .get();

      for (final v in vehicleSnap.docs) {
        batch.update(v.reference, {'status': 'Available'});
      }
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
      _dispatchStatus = "Validated";
      _currentDispatchId = null;
      _currentAlertId = null;
      _isTeamLeader = false;
      _currentAlertType = null;
      _currentDispatchTimestampText = "";
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Incident validated. All teams cleared.")),
    );
  }

  Future<void> _validateIncident() async {
    if (_currentDispatchId == null || _currentAlertId == null) return;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "Confirm Validation",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text('Are you sure you want to validate this incident?'),
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
            child: const Text("Validate"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final currentUser = await _getCurrentUserData();
      if (currentUser == null) return;

      final userId = currentUser['docId'].toString();
      final userName = (currentUser['name'] ?? 'Responder').toString();
      final userEmail = (currentUser['email'] ?? '').toString().toLowerCase();
      final userTeamId = (currentUser['teamId'] ?? '').toString();
      final userTeamName = (currentUser['teamName'] ?? '').toString();

      final currentDispatch = await FirebaseFirestore.instance
          .collection('dispatches')
          .doc(_currentDispatchId)
          .get();

      if (!currentDispatch.exists) return;

      final currentData = currentDispatch.data() as Map<String, dynamic>;
      final alertId = currentData["alertId"]?.toString();

      if (alertId == null || alertId.isEmpty) return;

      final alertDoc = await FirebaseFirestore.instance
          .collection('alerts')
          .doc(alertId)
          .get();

      if (alertDoc.exists) {
        final alertData = alertDoc.data() as Map<String, dynamic>;
        if ((alertData['status'] ?? '').toString() == 'Validated') {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This alert is already validated.')),
          );
          return;
        }
      }

      final activeDispatches = await FirebaseFirestore.instance
          .collection('dispatches')
          .where('alertId', isEqualTo: alertId)
          .where('status', isEqualTo: 'Dispatched')
          .get();

      if (activeDispatches.docs.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No active dispatched teams found.")),
        );
        return;
      }

      bool isLeaderVote = false;
      final Set<String> allowedResponderIds = {};
      final Set<String> allowedResponderEmails = {};

      for (final doc in activeDispatches.docs) {
        final data = doc.data();

        if (data['leaderId'] != null &&
            data['leaderId'].toString().trim().isNotEmpty) {
          if (data['leaderId'].toString() == userId) {
            isLeaderVote = true;
          }
        }

        final responders = (data['responders'] as List<dynamic>? ?? []);
        for (final r in responders) {
          if (r is Map) {
            final rid = (r['id'] ?? '').toString().trim();
            final remail = (r['email'] ?? '').toString().toLowerCase().trim();
            if (rid.isNotEmpty) allowedResponderIds.add(rid);
            if (remail.isNotEmpty) allowedResponderEmails.add(remail);
            if (rid == userId || remail == userEmail) {
              final leaderId = (r['leaderId'] ?? '').toString().trim();
              if (leaderId.isNotEmpty && leaderId == userId) {
                isLeaderVote = true;
              }
            }
          }
        }

        final members = (data['members'] as List<dynamic>? ?? []);
        for (final m in members) {
          if (m is Map) {
            final mid = (m['id'] ?? '').toString().trim();
            final memail = (m['email'] ?? '').toString().toLowerCase().trim();
            if (mid.isNotEmpty) allowedResponderIds.add(mid);
            if (memail.isNotEmpty) allowedResponderEmails.add(memail);
          }
        }

        String? matchedTeamId;
        String? matchedTeamName;

        for (final r in responders) {
          if (r is Map) {
            final rid = (r['id'] ?? '').toString().trim();
            final remail = (r['email'] ?? '').toString().toLowerCase().trim();
            if (rid == userId || remail == userEmail) {
              matchedTeamId = (r['teamId'] ?? '').toString().trim();
              matchedTeamName = (r['teamName'] ?? r['team'] ?? '')
                  .toString()
                  .trim();
              break;
            }
          }
        }

        if (matchedTeamId == null && matchedTeamName == null) {
          for (final m in members) {
            if (m is Map) {
              final mid = (m['id'] ?? '').toString().trim();
              final memail = (m['email'] ?? '').toString().toLowerCase().trim();
              if (mid == userId || memail == userEmail) {
                matchedTeamId = (m['teamId'] ?? '').toString().trim();
                matchedTeamName = (m['teamName'] ?? '').toString().trim();
                break;
              }
            }
          }
        }

        matchedTeamId = (matchedTeamId == null || matchedTeamId.isEmpty)
            ? userTeamId
            : matchedTeamId;
        matchedTeamName = (matchedTeamName == null || matchedTeamName.isEmpty)
            ? userTeamName
            : matchedTeamName;

        if (!isLeaderVote && matchedTeamId.isNotEmpty) {
          final teamDoc = await FirebaseFirestore.instance
              .collection('teams')
              .doc(matchedTeamId)
              .get();

          if (teamDoc.exists) {
            final teamData = teamDoc.data() as Map<String, dynamic>;
            final leaderId = (teamData['leaderId'] ?? '').toString().trim();
            if (leaderId == userId) {
              isLeaderVote = true;
            }
          }
        } else if (!isLeaderVote && matchedTeamName.isNotEmpty) {
          final teamSnap = await FirebaseFirestore.instance
              .collection('teams')
              .where('teamName', isEqualTo: matchedTeamName)
              .limit(1)
              .get();

          if (teamSnap.docs.isNotEmpty) {
            final teamData = teamSnap.docs.first.data();
            final leaderId = (teamData['leaderId'] ?? '').toString().trim();
            if (leaderId == userId) {
              isLeaderVote = true;
            }
          }
        }
      }

      final isAllowedResponder =
          allowedResponderIds.contains(userId) ||
          allowedResponderEmails.contains(userEmail);

      if (!isAllowedResponder) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You are not part of this active dispatch.'),
          ),
        );
        return;
      }

      final voteRef = FirebaseFirestore.instance
          .collection('alerts')
          .doc(alertId)
          .collection('resolve_votes')
          .doc(userId);

      await voteRef.set({
        'userId': userId,
        'name': userName,
        'email': userEmail,
        'teamId': userTeamId,
        'teamName': userTeamName,
        'isLeader': isLeaderVote,
        'dispatchId': _currentDispatchId,
        'votedAt': FieldValue.serverTimestamp(),
      });

      final votesSnap = await FirebaseFirestore.instance
          .collection('alerts')
          .doc(alertId)
          .collection('resolve_votes')
          .get();

      int leaderVotes = 0;
      int memberVotes = 0;

      for (final doc in votesSnap.docs) {
        final data = doc.data();
        final votedUserId = (data['userId'] ?? '').toString().trim();
        final votedEmail = (data['email'] ?? '')
            .toString()
            .toLowerCase()
            .trim();
        final isAllowedVote =
            allowedResponderIds.contains(votedUserId) ||
            allowedResponderEmails.contains(votedEmail);

        if (!isAllowedVote) continue;

        final isLeader = data['isLeader'] == true;
        if (isLeader) {
          leaderVotes++;
        } else {
          memberVotes++;
        }
      }

      final bool shouldValidate = leaderVotes >= 1 || memberVotes >= 2;

      if (shouldValidate) {
        await _finalizeAlertValidation(alertId);
        return;
      }

      if (!mounted) return;

      if (isLeaderVote) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Leader confirmation received. Validating incident...',
            ),
          ),
        );
      } else {
        final remainingVotes = (2 - memberVotes).clamp(0, 2);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              remainingVotes > 0
                  ? 'Validation noted. Need $remainingVotes more member confirmation.'
                  : 'Validation noted.',
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("Validate error: $e");

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to validate incident: $e")),
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

  Future<void> _openNavigationToAlert({
    required double alertLat,
    required double alertLng,
    String? alertAddress,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return;

    try {
      final userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: user.email)
          .limit(1)
          .get();

      if (userQuery.docs.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Responder record not found.")),
        );
        return;
      }

      final userDoc = userQuery.docs.first;
      final userData = userDoc.data();

      String stationId = (userData['stationId'] ?? '').toString().trim();
      String stationName = (userData['stationName'] ?? '').toString().trim();
      String teamId = (userData['teamId'] ?? '').toString().trim();
      String teamName = (userData['teamName'] ?? '').toString().trim();

      // 1) Direct user station
      if (stationId.isNotEmpty) {
        final stationSnap = await FirebaseFirestore.instance
            .collection('stations')
            .doc(stationId)
            .get();

        if (stationSnap.exists) {
          final stationData = stationSnap.data() as Map<String, dynamic>;
          final stationLat = (stationData['latitude'] as num?)?.toDouble();
          final stationLng = (stationData['longitude'] as num?)?.toDouble();
          final stationAddress = (stationData['address'] ?? '')
              .toString()
              .trim();

          final resolvedStationName =
              (stationData['name']?.toString().trim().isNotEmpty ?? false)
              ? stationData['name'].toString().trim()
              : (stationName.isNotEmpty ? stationName : 'Station');

          if (stationLat == null || stationLng == null) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Station coordinates missing.")),
            );
            return;
          }

          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MapNavigationPage(
                stationLat: stationLat,
                stationLng: stationLng,
                stationAddress: stationAddress.isNotEmpty
                    ? stationAddress
                    : "No station address",
                stationName: resolvedStationName,
                alertLat: alertLat,
                alertLng: alertLng,
                alertAddress: alertAddress,
                apiKey: "AIzaSyC4Ai-W_V2M7qftiuQBYcnyCL8oqaDF680",
              ),
            ),
          );
          return;
        }
      }

      // 2) Fallback: resolve team first if teamId missing but teamName exists
      if (teamId.isEmpty && teamName.isNotEmpty) {
        final teamQuery = await FirebaseFirestore.instance
            .collection('teams')
            .where('teamName', isEqualTo: teamName)
            .limit(1)
            .get();

        if (teamQuery.docs.isNotEmpty) {
          teamId = teamQuery.docs.first.id;
        }
      }

      // 3) Fallback: get station from team document
      if (stationId.isEmpty && teamId.isNotEmpty) {
        final teamSnap = await FirebaseFirestore.instance
            .collection('teams')
            .doc(teamId)
            .get();

        if (teamSnap.exists) {
          final teamData = teamSnap.data() as Map<String, dynamic>;

          stationId = (teamData['stationId'] ?? '').toString().trim();

          if (stationName.isEmpty) {
            stationName = (teamData['stationName'] ?? '').toString().trim();
          }

          if (teamName.isEmpty) {
            teamName = (teamData['teamName'] ?? '').toString().trim();
          }

          if (stationId.isNotEmpty) {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(userDoc.id)
                .update({
                  'teamId': teamId,
                  if (teamName.isNotEmpty) 'teamName': teamName,
                  'stationId': stationId,
                  if (stationName.isNotEmpty) 'stationName': stationName,
                });
          }
        }
      }

      // 4) Fallback: resolve station by station teamIds/teamNames arrays
      if (stationId.isEmpty && teamId.isNotEmpty) {
        final stationByTeamId = await FirebaseFirestore.instance
            .collection('stations')
            .where('teamIds', arrayContains: teamId)
            .limit(1)
            .get();

        if (stationByTeamId.docs.isNotEmpty) {
          final stationDoc = stationByTeamId.docs.first;
          final stationData = stationDoc.data();

          stationId = stationDoc.id;

          if (stationName.isEmpty) {
            stationName = (stationData['name'] ?? '').toString().trim();
          }

          await FirebaseFirestore.instance
              .collection('users')
              .doc(userDoc.id)
              .update({
                'teamId': teamId,
                if (teamName.isNotEmpty) 'teamName': teamName,
                'stationId': stationId,
                if (stationName.isNotEmpty) 'stationName': stationName,
              });
        }
      }

      if (stationId.isEmpty && teamName.isNotEmpty) {
        final stationByTeamName = await FirebaseFirestore.instance
            .collection('stations')
            .where('teamNames', arrayContains: teamName)
            .limit(1)
            .get();

        if (stationByTeamName.docs.isNotEmpty) {
          final stationDoc = stationByTeamName.docs.first;
          final stationData = stationDoc.data();

          stationId = stationDoc.id;

          if (stationName.isEmpty) {
            stationName = (stationData['name'] ?? '').toString().trim();
          }

          await FirebaseFirestore.instance
              .collection('users')
              .doc(userDoc.id)
              .update({
                if (teamId.isNotEmpty) 'teamId': teamId,
                if (teamName.isNotEmpty) 'teamName': teamName,
                'stationId': stationId,
                if (stationName.isNotEmpty) 'stationName': stationName,
              });
        }
      }

      if (stationId.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Responder station cannot be found from team yet."),
          ),
        );
        return;
      }

      // 5) Open final station
      final stationSnap = await FirebaseFirestore.instance
          .collection('stations')
          .doc(stationId)
          .get();

      if (!stationSnap.exists) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Station record not found.")),
        );
        return;
      }

      final stationData = stationSnap.data() as Map<String, dynamic>;
      final stationLat = (stationData['latitude'] as num?)?.toDouble();
      final stationLng = (stationData['longitude'] as num?)?.toDouble();
      final stationAddress = (stationData['address'] ?? '').toString().trim();

      final resolvedStationName =
          (stationData['name']?.toString().trim().isNotEmpty ?? false)
          ? stationData['name'].toString().trim()
          : (stationName.isNotEmpty ? stationName : 'Station');

      if (stationLat == null || stationLng == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Station coordinates missing.")),
        );
        return;
      }

      // Save clean values back to user doc
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userDoc.id)
          .update({
            if (teamId.isNotEmpty) 'teamId': teamId,
            if (teamName.isNotEmpty) 'teamName': teamName,
            'stationId': stationId,
            'stationName': resolvedStationName,
          });

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MapNavigationPage(
            stationLat: stationLat,
            stationLng: stationLng,
            stationAddress: stationAddress.isNotEmpty
                ? stationAddress
                : "No station address",
            stationName: resolvedStationName,
            alertLat: alertLat,
            alertLng: alertLng,
            alertAddress: alertAddress,
            apiKey: "AIzaSyC4Ai-W_V2M7qftiuQBYcnyCL8oqaDF680",
          ),
        ),
      );
    } catch (e) {
      debugPrint("Navigation error: $e");
      if (!mounted) return;
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

class ValidationFormPage extends StatefulWidget {
  final Future<String?> Function(ImageSource source) onPickImageBase64;
  final Future<void> Function({
    required List<String> fireTypes,
    required String sourceOfFire,
    required bool injuredOrTrapped,
    required List<String> resourcesNeeded,
    required String remarks,
    required bool skippedBecauseRadioed,
    String? actualFireImageBase64,
  })
  onSubmit;

  const ValidationFormPage({
    super.key,
    required this.onPickImageBase64,
    required this.onSubmit,
  });

  @override
  State<ValidationFormPage> createState() => _ValidationFormPageState();
}

class _ValidationFormPageState extends State<ValidationFormPage> {
  final List<String> _selectedFireTypes = [];
  final List<String> _selectedResources = [];
  final TextEditingController _sourceController = TextEditingController();
  final TextEditingController _remarksController = TextEditingController();

  bool _injuredOrTrapped = false;
  bool _skippedBecauseRadioed = false;
  bool _isSubmitting = false;
  String? _actualFireImageBase64;

  static const List<String> _fireTypeOptions = [
    'Residential',
    'Electrical',
    'Vehicular',
    'Structural',
    'Grass',
    'Industrial',
    'Other',
  ];

  static const List<String> _resourceOptions = [
    'Backup',
    'Ambulance',
    'Police',
    'Additional Fire Truck',
  ];

  @override
  void dispose() {
    _sourceController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Widget _sectionCard({required Widget child}) {
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
      child: child,
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.bold,
        color: Color(0xFFB71C1C),
      ),
    );
  }

  Widget _buildCheckItem({
    required String label,
    required bool value,
    required ValueChanged<bool?>? onChanged,
  }) {
    return CheckboxListTile(
      value: value,
      onChanged: onChanged,

      activeColor: const Color(0xFFB71C1C),

      fillColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.selected)) {
          return const Color(0xFFB71C1C);
        }
        return Colors.white;
      }),

      side: const BorderSide(color: Colors.grey),

      checkColor: Colors.white,

      contentPadding: EdgeInsets.zero,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,

      title: Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Colors.black,
        ),
      ),
    );
  }

  Future<void> _handleSubmit() async {
    final hasMeaningfulInput =
        _selectedFireTypes.isNotEmpty ||
        _sourceController.text.trim().isNotEmpty ||
        _injuredOrTrapped ||
        _selectedResources.isNotEmpty ||
        _remarksController.text.trim().isNotEmpty ||
        (_actualFireImageBase64 != null &&
            _actualFireImageBase64!.trim().isNotEmpty);

    if (!_skippedBecauseRadioed && !hasMeaningfulInput) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Please fill in at least one validation detail or choose skip.",
          ),
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      await widget.onSubmit(
        fireTypes: _selectedFireTypes,
        sourceOfFire: _sourceController.text,
        injuredOrTrapped: _injuredOrTrapped,
        resourcesNeeded: _selectedResources,
        remarks: _remarksController.text,
        skippedBecauseRadioed: _skippedBecauseRadioed,
        actualFireImageBase64: _actualFireImageBase64,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to save validation form: $e")),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.light().copyWith(
        scaffoldBackgroundColor: const Color(0xFFF7F7FA),

        // ✅ force all text to black
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: Colors.black,
          displayColor: Colors.black,
        ),

        // ✅ input field styling
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF7F7FA),
          hintStyle: const TextStyle(color: Colors.grey),
        ),

        // ✅ checkbox / switch colors
        checkboxTheme: CheckboxThemeData(
          fillColor: MaterialStateProperty.all(const Color(0xFFB71C1C)),
        ),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F7FA),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(
              Icons.chevron_left,
              size: 30,
              color: Color(0xFFB71C1C),
            ),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            "Validation Form",
            style: TextStyle(
              color: Color(0xFFB71C1C),
              fontWeight: FontWeight.bold,
              fontSize: 19,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionCard(
                  child: _buildCheckItem(
                    label: "Skip detailed form, already radioed",
                    value: _skippedBecauseRadioed,
                    onChanged: (checked) {
                      setState(() {
                        _skippedBecauseRadioed = checked ?? false;

                        if (_skippedBecauseRadioed) {
                          _selectedFireTypes.clear();
                          _selectedResources.clear();
                          _sourceController.clear();
                          _remarksController.clear();
                          _injuredOrTrapped = false;
                          _actualFireImageBase64 = null;
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(height: 12),
                _sectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle("Type of Fire"),
                      const SizedBox(height: 8),
                      ..._fireTypeOptions.map(
                        (type) => _buildCheckItem(
                          label: type,
                          value: _selectedFireTypes.contains(type),
                          onChanged: _skippedBecauseRadioed
                              ? null
                              : (checked) {
                                  setState(() {
                                    if (checked == true) {
                                      if (!_selectedFireTypes.contains(type)) {
                                        _selectedFireTypes.add(type);
                                      }
                                    } else {
                                      _selectedFireTypes.remove(type);
                                    }
                                  });
                                },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _sectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle("Source of Fire, if known"),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _sourceController,
                        enabled: !_skippedBecauseRadioed,
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText: "Ex. Kitchen, wiring, outlet, engine",
                          filled: true,
                          fillColor: const Color(0xFFF7F7FA),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _sectionCard(
                  child: _buildCheckItem(
                    label: "Injured / Trapped",
                    value: _injuredOrTrapped,
                    onChanged: _skippedBecauseRadioed
                        ? null
                        : (checked) {
                            setState(() {
                              _injuredOrTrapped = checked ?? false;
                            });
                          },
                  ),
                ),
                const SizedBox(height: 12),
                _sectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle("Resources Needed"),
                      const SizedBox(height: 8),
                      ..._resourceOptions.map(
                        (item) => _buildCheckItem(
                          label: item,
                          value: _selectedResources.contains(item),
                          onChanged: _skippedBecauseRadioed
                              ? null
                              : (checked) {
                                  setState(() {
                                    if (checked == true) {
                                      if (!_selectedResources.contains(item)) {
                                        _selectedResources.add(item);
                                      }
                                    } else {
                                      _selectedResources.remove(item);
                                    }
                                  });
                                },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _sectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle("Actual Fire Photo"),
                      const SizedBox(height: 10),
                      if (_actualFireImageBase64 != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.memory(
                            base64Decode(_actualFireImageBase64!),
                            height: 190,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        )
                      else
                        Container(
                          height: 150,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF2F2F7),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE0E0E0)),
                          ),
                          child: const Center(
                            child: Text(
                              "No validation photo selected",
                              style: TextStyle(
                                color: Color(0xFF636366),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _skippedBecauseRadioed
                                  ? null
                                  : () async {
                                      final picked = await widget
                                          .onPickImageBase64(
                                            ImageSource.camera,
                                          );
                                      if (picked == null) return;
                                      setState(() {
                                        _actualFireImageBase64 = picked;
                                      });
                                    },
                              icon: const Icon(Icons.camera_alt_rounded),
                              label: const Text("Camera"),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _skippedBecauseRadioed
                                  ? null
                                  : () async {
                                      final picked = await widget
                                          .onPickImageBase64(
                                            ImageSource.gallery,
                                          );
                                      if (picked == null) return;
                                      setState(() {
                                        _actualFireImageBase64 = picked;
                                      });
                                    },
                              icon: const Icon(Icons.photo_library_rounded),
                              label: const Text("Gallery"),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _sectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle("Remarks"),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _remarksController,
                        enabled: !_skippedBecauseRadioed,
                        minLines: 3,
                        maxLines: 5,
                        decoration: InputDecoration(
                          hintText:
                              "Ex. Visible flames, heavy smoke, waiting for backup",
                          filled: true,
                          fillColor: const Color(0xFFF7F7FA),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _handleSubmit,
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.verified_rounded),
                    label: Text(
                      _isSubmitting ? "Submitting..." : "Submit Validation",
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
