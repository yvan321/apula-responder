import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

// SCREENS
import 'screens/splash_screen.dart';
import 'screens/login/login_screen.dart';
import 'screens/register/register_screen.dart';
import 'screens/app/home/home_page.dart';
import 'screens/register/verification_screen.dart';
import 'screens/register/setpassword_screen.dart';

/// 🔔 GLOBAL NAVIGATOR KEY
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// 🔔 LOCAL NOTIFICATION
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

/// 🔔 CHANNEL (VERY IMPORTANT)
const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'high_importance_channel',
  'Emergency Dispatch Alerts',
  description: 'Fire dispatch emergency alerts',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
);

/// 🔥 BACKGROUND HANDLER (APP CLOSED / BACKGROUND)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  print("🔥 BACKGROUND MESSAGE RECEIVED");

  await flutterLocalNotificationsPlugin.show(
    message.hashCode,
    message.notification?.title ?? "🚨 DISPATCH ALERT",
    message.notification?.body ?? "New incident",
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'high_importance_channel',
        'Emergency Dispatch Alerts',
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        icon: '@mipmap/ic_launcher',
      ),
    ),
  );
}

/// 🔔 INIT LOCAL NOTIFICATIONS
Future<void> setupLocalNotifications() async {
  final androidPlugin =
      flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

  await androidPlugin?.createNotificationChannel(channel);

  const initSettings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  );

  await flutterLocalNotificationsPlugin.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (response) {
      navigatorKey.currentState?.pushNamed('/home');
    },
  );
}

/// 🔥 INIT FCM
Future<void> initFCM() async {
  FirebaseMessaging messaging = FirebaseMessaging.instance;

  // Request permission
  await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  // Get token
  String? token = await messaging.getToken();
  print("📱 TOKEN: $token");

  await saveToken(token);

  // Refresh token
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
    print("♻️ TOKEN REFRESHED: $newToken");
    await saveToken(newToken);
  });

  /// 🔥 FOREGROUND (APP OPEN)
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print("🔥 FOREGROUND MESSAGE");

    flutterLocalNotificationsPlugin.show(
      message.hashCode,
      message.notification?.title ?? "🚨 DISPATCH",
      message.notification?.body ?? "New fire incident",
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel',
          'Emergency Dispatch Alerts',
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  });

  /// 🔥 CLICK NOTIFICATION (BACKGROUND → OPEN APP)
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    navigatorKey.currentState?.pushNamed('/home');
  });

  /// 🔥 TERMINATED → OPEN
  RemoteMessage? initialMessage =
      await FirebaseMessaging.instance.getInitialMessage();

  if (initialMessage != null) {
    navigatorKey.currentState?.pushNamed('/home');
  }
}

/// 🔥 SAVE TOKEN
Future<void> saveToken(String? token) async {
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

  print("✅ TOKEN SAVED");
}

/// 🔥 MAIN
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  /// 🔥 BACKGROUND HANDLER REGISTER
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await setupLocalNotifications();

  /// 🔥 ANDROID 13 PERMISSION
  if (await Permission.notification.isDenied) {
    await Permission.notification.request();
  }

  await initFCM();

  runApp(const MyApp());
}

/// 🔥 APP
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();

    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null) {
        String? token = await FirebaseMessaging.instance.getToken();
        await saveToken(token);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: "Apula",
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/home': (context) => const HomePage(),
        '/verification': (context) =>
            VerificationScreen(email: ModalRoute.of(context)!.settings.arguments as String),
        '/setpassword': (context) =>
            SetPasswordScreen(email: ModalRoute.of(context)!.settings.arguments as String),
      },
    );
  }
}