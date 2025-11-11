import 'package:flutter/material.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    const redColor = Color(0xFFA30000);
    final theme = Theme.of(context);
    final textColor = theme.brightness == Brightness.dark
        ? Colors.white
        : Colors.black87;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // 🔙 Top Bar with Back Button + Title
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 20, left: 10, right: 10),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [redColor, Colors.black],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(30),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      child: const Icon(
                        Icons.chevron_left,
                        size: 30,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    "About",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 40), // balances the layout
                ],
              ),
            ),

            // 📜 Main Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 20),

                    // 🔥 App Logo
                    Image.asset(
                      'assets/logo.png',
                      width: 130,
                      height: 130,
                    ),
                    const SizedBox(height: 30),

                    // 🧠 App Description
                    Text(
                      "Apula is a CNN-powered fire detection and alert system designed "
                      "for both responders and community safety. It integrates CCTV "
                      "footage, thermal imaging, and IoT sensors to detect early fire "
                      "indicators such as smoke, small flames, and temperature changes. "
                      "\n\nWith real-time alerts, live monitoring, and synchronized notifications, "
                      "Apula ensures quick response, efficient dispatching, and enhanced "
                      "fire prevention in residential and commercial areas.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 16,
                        height: 1.6,
                      ),
                    ),

                    const SizedBox(height: 40),

                    // 🧰 Version Info
                    Column(
                      children: [
                        Text(
                          "Version 1.0.0",
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Developed by Team Apula",
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 40),

                    // ⚙️ Footer or Tagline
                    Text(
                      "“Fast Response. Smarter Detection. Safer Communities.”",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: redColor.withOpacity(0.8),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
