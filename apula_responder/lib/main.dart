import 'package:flutter/material.dart';

import 'screens/splash_screen.dart';
import 'screens/login/login_screen.dart';
import 'screens/register/register_screen.dart';
import 'screens/app/home/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
      },
    );
  }
}
