import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lottie/lottie.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  @override
  void initState() {
    super.initState();
    final email = FirebaseAuth.instance.currentUser?.email;
    print("📧 Logged in as: $email");
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final responderEmail = FirebaseAuth.instance.currentUser?.email;

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

              // 🔔 Firestore Stream
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('dispatches')
                      .where('responderEmail', isEqualTo: responderEmail)
                      .orderBy('timestamp', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          "⚠️ Firestore Error: ${snapshot.error}",
                          style: const TextStyle(color: Colors.red),
                        ),
                      );
                    }

                    // ✅ Debug
                    print("📄 Dispatch notifications count: ${snapshot.data?.docs.length}");

                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return _buildEmptyState();
                    }

                    final notifications = snapshot.data!.docs;

                    return ListView.builder(
                      itemCount: notifications.length,
                      itemBuilder: (context, index) {
                        final data =
                            notifications[index].data() as Map<String, dynamic>;
                        final status = data["status"] ?? "Dispatched";

                        // Safely parse timestamp
                        String formattedTime = "N/A";
                        if (data["timestamp"] is Timestamp) {
                          final ts = (data["timestamp"] as Timestamp).toDate();
                          formattedTime =
                              "${ts.year}-${ts.month}-${ts.day} ${ts.hour}:${ts.minute.toString().padLeft(2, '0')}";
                        } else if (data["timestamp"] is String) {
                          formattedTime = data["timestamp"];
                        }

                        // Icons & colors by status
                        Color typeColor;
                        IconData typeIcon;

                        switch (status) {
                          case "Dispatched":
                            typeColor = Colors.orangeAccent;
                            typeIcon = Icons.fire_truck_rounded;
                            break;
                          case "Resolved":
                            typeColor = Colors.green;
                            typeIcon = Icons.check_circle_outline;
                            break;
                          default:
                            typeColor = Colors.redAccent;
                            typeIcon = Icons.local_fire_department;
                        }

                        return Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: typeColor.withOpacity(0.4),
                              width: 1,
                            ),
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
                                      data["alertType"] ?? "New Alert",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      "Location: ${data["alertLocation"] ?? "Unknown"}",
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      "Status: $status",
                                      style: TextStyle(
                                        color: typeColor,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      "Reported by: ${data["userReported"] ?? "Unknown"}",
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      "Time: $formattedTime",
                                      style: TextStyle(
                                        color: Colors.grey[500],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 🧱 Empty State Animation
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
}
