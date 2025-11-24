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

/// 🔥 Background FCM Handler
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("🔔 Background Notification: ${message.notification?.title}");
}

/// 🔔 Local Notifications Plugin
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

/// 🔔 Setup notification channel
Future<void> _setupLocalNotifications() async {
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'This channel is used for critical alerts.',
    importance: Importance.high,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  const InitializationSettings initSettings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  );

  await flutterLocalNotificationsPlugin.initialize(initSettings);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await _setupLocalNotifications();

  runApp(const MyApp());
}

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

  /// 🚀 Initialize Firebase Cloud Messaging
  Future<void> _initFCM() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // Request permission (iOS only)
    await messaging.requestPermission();

    // Get token
    String? token = await messaging.getToken();
    print("📱 FCM Device Token: $token");

    // 🔥 SAVE TOKEN AUTOMATICALLY TO FIRESTORE
    await _saveTokenToFirestore(token);

    // Handle token refresh
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      print("♻️ Token refreshed: $newToken");
      _saveTokenToFirestore(newToken);
    });

    // 🔔 Foreground Notifications
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print("🔔 Foreground: ${message.notification?.title}");

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

    // 🔔 App opened via notification
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      print("📨 Notification opened app: ${message.data}");
    });
  }

  /// 🔥 SAVE TOKEN FUNCTION
  Future<void> _saveTokenToFirestore(String? token) async {
    if (token == null) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      // User is logged in → save under their UID
      await FirebaseFirestore.instance
          .collection("fcm_tokens")
          .doc(user.uid)
          .set({
        "token": token,
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print("🔥 Token saved for user ${user.uid}");
    } else {
      // No user logged in → store by token
      await FirebaseFirestore.instance
          .collection("fcm_tokens")
          .doc(token)
          .set({
        "token": token,
        "updatedAt": FieldValue.serverTimestamp(),
        "user": null,
      });

      print("🔥 Token saved as guest");
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryRed = Color(0xFFA30000);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Apula",
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryRed,
        ).copyWith(primary: primaryRed, secondary: primaryRed),
      ),
      darkTheme: ThemeData.dark().copyWith(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryRed,
          brightness: Brightness.dark,
        ).copyWith(primary: primaryRed, secondary: primaryRed),
      ),

      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/home': (context) => const HomePage(),
        '/verification': (context) {
          final email =
              ModalRoute.of(context)!.settings.arguments as String;
          return VerificationScreen(email: email);
        },
        '/setpassword': (context) {
          final email =
              ModalRoute.of(context)!.settings.arguments as String;
          return SetPasswordScreen(email: email);
        },
      },
    );
  }
}
