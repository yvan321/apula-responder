import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  int _selectedIndex = 2; // 🔔 Current tab index (Notifications)

  // 🧠 Mock data (you can later connect to Firestore)
  final List<Map<String, String>> mockNotifications = [
    {
      "title": "🚨 Fire Alert: Molino 3",
      "message": "Alpha Team 2 dispatched for fire suppression response.",
      "time": "2 mins ago",
      "type": "alert",
    },
    {
      "title": "🔥 Update: Warehouse Fire - Niog",
      "message": "Situation under control. Awaiting final clearance.",
      "time": "10 mins ago",
      "type": "update",
    },
    {
      "title": "✅ Resolved: Vehicle Fire - Talaba",
      "message": "Charlie Unit 3 confirmed incident cleared.",
      "time": "25 mins ago",
      "type": "resolved",
    },
    {
      "title": "🧯 Fire Drill Scheduled",
      "message": "Training session for all responders at HQ - Nov 15, 9 AM.",
      "time": "1 hr ago",
      "type": "info",
    },
  ];

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, '/home');
        break;
      case 1:
        Navigator.pushReplacementNamed(context, '/dispatch');
        break;
      case 2:
        break;
      case 3:
        Navigator.pushReplacementNamed(context, '/settings');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🔙 Back Button
              InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(30),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(shape: BoxShape.circle),
                  child: Icon(
                    Icons.chevron_left,
                    size: 30,
                    color: colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // ✨ Title
              Text(
                "Notifications",
                style: TextStyle(
                  color: colorScheme.primary,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),

              // 📜 Notification List or Empty Animation
              Expanded(
                child: mockNotifications.isEmpty
                    ? _buildEmptyState()
                    : _buildNotificationList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 🧱 Empty notification animation
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Lottie.asset("assets/empty.json", height: 200),
          const SizedBox(height: 10),
          const Text(
            "No notifications yet.",
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// 🧱 Notification list builder
  Widget _buildNotificationList() {
    return ListView.builder(
      itemCount: mockNotifications.length,
      itemBuilder: (context, index) {
        final notif = mockNotifications[index];
        final type = notif["type"];

        Color typeColor;
        IconData typeIcon;

        switch (type) {
          case "alert":
            typeColor = Colors.redAccent;
            typeIcon = Icons.local_fire_department_rounded;
            break;
          case "update":
            typeColor = Colors.orangeAccent;
            typeIcon = Icons.sync_rounded;
            break;
          case "resolved":
            typeColor = Colors.green;
            typeIcon = Icons.check_circle_outline;
            break;
          case "info":
            typeColor = Colors.blueAccent;
            typeIcon = Icons.info_outline;
            break;
          default:
            typeColor = Colors.grey;
            typeIcon = Icons.notifications_none;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: typeColor.withOpacity(0.4), width: 1),
            color: typeColor.withOpacity(0.05),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: typeColor.withOpacity(0.15),
                child: Icon(typeIcon, color: typeColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notif["title"] ?? "",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      notif["message"] ?? "",
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      notif["time"] ?? "",
                      style:
                          TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
