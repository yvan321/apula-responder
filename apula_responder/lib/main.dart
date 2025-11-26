import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'firebase_options.dart';

// SCREENS
import 'screens/splash_screen.dart';
import 'screens/login/login_screen.dart';
import 'screens/register/register_screen.dart';
import 'screens/app/home/home_page.dart';
import 'screens/register/verification_screen.dart';
import 'screens/register/setpassword_screen.dart';

/// ---------------------------------------------------------------
/// 🔔 GLOBAL NAVIGATOR KEY (allows navigation outside widget tree)
/// ---------------------------------------------------------------
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// ---------------------------------------------------------------
/// 🔔 Background FCM Handler
/// ---------------------------------------------------------------
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("🔕 Background Notification: ${message.notification?.title}");
}

/// ---------------------------------------------------------------
/// 🔔 Local Notifications Plugin
/// ---------------------------------------------------------------
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

/// ---------------------------------------------------------------
/// 🔔 Set up Notification Channel for Android
/// ---------------------------------------------------------------
Future<void> _setupLocalNotifications() async {
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'Used for critical dispatcher alerts',
    importance: Importance.high,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);

  const InitializationSettings initSettings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  );

  await flutterLocalNotificationsPlugin.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (details) {
      // Notification tapped while app is open
      navigatorKey.currentState?.pushNamed('/home');
    },
  );
}

/// ---------------------------------------------------------------
/// 🔥 MAIN
/// ---------------------------------------------------------------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Background notification handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await _setupLocalNotifications();

  runApp(const MyApp());
}

/// ---------------------------------------------------------------
/// APP ROOT
/// ---------------------------------------------------------------
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    _initFCM();
  }

  /// -----------------------------------------------------------
  /// 🚀 Initialize Firebase Cloud Messaging listeners
  /// -----------------------------------------------------------
  Future<void> _initFCM() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // Request permissions for iOS (safe on Android)
    await messaging.requestPermission();

    // Print token on app start
    String? token = await messaging.getToken();
    print("📱 FCM Device Token: $token");

    // Save token to Firestore
    await _saveTokenToFirestore(token);

    // Handle token refresh
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      print("♻️ Token refreshed: $newToken");
      _saveTokenToFirestore(newToken);
    });

    // -------------------------------------------------------
    // 🔔 Foreground notifications
    // -------------------------------------------------------
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print("🔔 Foreground Notification: ${message.notification?.title}");

      if (message.notification != null) {
        flutterLocalNotificationsPlugin.show(
          message.hashCode,
          message.notification!.title,
          message.notification!.body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'high_importance_channel',
              'High Importance Notifications',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
        );
      }
    });

    // -------------------------------------------------------
    // 🔔 App opened from background (tap on notification)
    // -------------------------------------------------------
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print("📨 App opened from background by notification: ${message.data}");
      navigatorKey.currentState?.pushNamed('/home');
    });

    // -------------------------------------------------------
    // 🔔 App opened from terminated state
    // -------------------------------------------------------
    RemoteMessage? initialMessage = await FirebaseMessaging.instance
        .getInitialMessage();
    if (initialMessage != null) {
      print(
        "🚀 App launched by notification (terminated): ${initialMessage.data}",
      );
      navigatorKey.currentState?.pushNamed('/home');
    }
  }

  /// -----------------------------------------------------------
  /// 🔥 SAVE TOKEN WITH userId + email (admin panel requires this)
  /// -----------------------------------------------------------
  Future<void> _saveTokenToFirestore(String? token) async {
    if (token == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection("fcm_tokens").doc(user.uid).set(
      {
        "userId": user.uid, // ✅ REQUIRED
        "email": user.email, // ✅ REQUIRED
        "token": token, // FCM token
        "updatedAt": FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    print("🔥 Token saved for user ${user.uid}");
  }

  /// -----------------------------------------------------------
  /// UI BUILD
  /// -----------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    const primaryRed = Color(0xFFA30000);

    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: "Apula",
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: primaryRed),
      ),

      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/home': (context) => const HomePage(),
        '/verification': (context) {
          final email = ModalRoute.of(context)!.settings.arguments as String;
          return VerificationScreen(email: email);
        },
        '/setpassword': (context) {
          final email = ModalRoute.of(context)!.settings.arguments as String;
          return SetPasswordScreen(email: email);
        },
      },
    );
  }
}
