import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import 'firebase_options.dart';

// SCREENS
import 'screens/splash_screen.dart';
import 'screens/login/login_screen.dart';
import 'screens/register/register_screen.dart';
import 'screens/app/home/home_page.dart';
import 'screens/register/verification_screen.dart';
import 'screens/register/setpassword_screen.dart';

/// ---------------------------------------------------------------
/// 🔔 GLOBAL NAVIGATOR KEY
/// ---------------------------------------------------------------
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// ---------------------------------------------------------------
/// 🔔 BACKGROUND FCM HANDLER
/// ---------------------------------------------------------------
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  print("🔥 BACKGROUND FCM RECEIVED");
  print(message.data);
}

/// ---------------------------------------------------------------
/// 🔔 Local Notifications Plugin
/// ---------------------------------------------------------------
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> _setupLocalNotifications() async {
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'high_importance_channel',
    'Emergency Dispatch Alerts',
    description: 'Fire dispatch emergency alerts',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
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

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await _setupLocalNotifications();

  // ⭐ REQUEST ANDROID 13+ NOTIFICATION PERMISSION
  if (await Permission.notification.isDenied) {
    await Permission.notification.request();
  }

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
  /// 🚀 Firebase Messaging Init
  /// -----------------------------------------------------------
  Future<void> _initFCM() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    await messaging.requestPermission();
    String? token = await messaging.getToken();
    print("📱 FCM Device Token: $token");

    await _saveTokenToFirestore(token);

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      print("♻️ Token refreshed: $newToken");
      _saveTokenToFirestore(newToken);
    });

    // Foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
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

    // Background tap
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      navigatorKey.currentState?.pushNamed('/home');
    });

    // Terminated state
    RemoteMessage? initialMessage = await FirebaseMessaging.instance
        .getInitialMessage();
    if (initialMessage != null) {
      navigatorKey.currentState?.pushNamed('/home');
    }
  }

  /// -----------------------------------------------------------
  /// 🔥 SAVE FCM TOKEN
  /// -----------------------------------------------------------
  Future<void> _saveTokenToFirestore(String? token) async {
    if (token == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection("fcm_tokens")
        .doc(user.uid)
        .set({
          "userId": user.uid,
          "email": user.email,
          "token": token,
          "updatedAt": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

    print("🔥 Token saved for user ${user.uid}");
  }

  /// -----------------------------------------------------------
  /// UI BUILD — WITH SYSTEM THEME SUPPORT
  /// -----------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    const primaryRed = Color(0xFFA30000);

    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: "Apula",

      themeMode: ThemeMode.system,

      // 🌞 LIGHT THEME
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(seedColor: primaryRed),
        scaffoldBackgroundColor: Colors.white,
      ),

      // 🌙 DARK THEME
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryRed,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
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
