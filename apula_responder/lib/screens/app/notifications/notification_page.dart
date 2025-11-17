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
    print("📧 Logged in (notifications): $email");
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentEmail = FirebaseAuth.instance.currentUser?.email;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back Button
              InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(30),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.chevron_left,
                    size: 30,
                    color: colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Page Title
              Text(
                "Notifications",
                style: TextStyle(
                  color: colorScheme.primary,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),

              // Firestore Stream (FIXED)
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('dispatches')
                      .where('responderEmails', arrayContains: currentEmail)
                      .orderBy('timestamp', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          "⚠ Firestore Error:\n${snapshot.error}",
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red),
                        ),
                      );
                    }

                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return _emptyState();
                    }

                    final docs = snapshot.data!.docs;

                    print("🔔 Notification docs: ${docs.length}");

                    return ListView.builder(
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data =
                            docs[index].data() as Map<String, dynamic>;

                        final String status = data['status'] ?? "Unknown";
                        final List<dynamic> responders =
                            data['responders'] ?? [];

                        // find the data of the current responder
                        final me = responders.firstWhere(
                          (r) => r["email"] == currentEmail,
                          orElse: () => null,
                        );

                        String formattedTime = "N/A";
                        if (data["timestamp"] is Timestamp) {
                          final ts = (data["timestamp"] as Timestamp).toDate();
                          formattedTime =
                              "${ts.year}-${ts.month}-${ts.day} ${ts.hour}:${ts.minute.toString().padLeft(2, '0')}";
                        }

                        // Status colors + icons
                        Color color;
                        IconData icon;

                        if (status == "Resolved") {
                          color = Colors.green;
                          icon = Icons.check_circle_outline;
                        } else {
                          color = Colors.orange;
                          icon = Icons.fire_truck_rounded;
                        }

                        return Container(
                          padding: const EdgeInsets.all(16),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: color.withOpacity(0.4)),
                            color: color.withOpacity(0.05),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: color.withOpacity(0.2),
                                child: Icon(icon, color: color),
                              ),
                              const SizedBox(width: 12),

                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      data["alertType"] ?? "Fire Alert",
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
                                      "You: ${me?["name"] ?? "Responder"}",
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                    const SizedBox(height: 6),

                                    Text(
                                      "Status: $status",
                                      style: TextStyle(
                                        color: color,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 6),

                                    Text(
                                      "Reported by: ${data["userReported"] ?? "Unknown"}",
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    const SizedBox(height: 6),

                                    Text(
                                      "Time: $formattedTime",
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              )
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

  // empty state lottie
  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Lottie.asset("assets/empty.json", height: 200),
          const SizedBox(height: 10),
          const Text(
            "No notifications yet.",
            style: TextStyle(color: Colors.grey, fontSize: 16),
          )
        ],
      ),
    );
  }
}
