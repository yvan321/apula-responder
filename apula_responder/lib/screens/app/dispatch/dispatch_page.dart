import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DispatchPage extends StatefulWidget {
  final List<String> devices;
  const DispatchPage({super.key, required this.devices});

  @override
  State<DispatchPage> createState() => _DispatchPageState();
}

class _DispatchPageState extends State<DispatchPage> {
  int _prevCount = 0; // for detecting new dispatches

  @override
  void initState() {
    super.initState();
    // ✅ Print logged-in responder email for debugging
    final email = FirebaseAuth.instance.currentUser?.email;
    print("📧 Logged in as: $email");
  }

  @override
  Widget build(BuildContext context) {
    final currentEmail = FirebaseAuth.instance.currentUser?.email;

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
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // ✨ Title
              Text(
                "Dispatches",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),

              // 🚒 Real-time Dispatch List
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('dispatches')
                      .where('responderEmail', isEqualTo: currentEmail)
                      .orderBy('timestamp', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          "⚠️ Firestore error: ${snapshot.error}",
                          style: const TextStyle(color: Colors.red),
                        ),
                      );
                    }

                    // ✅ Debug: Print the document count
                    print("📄 Dispatch docs count: ${snapshot.data?.docs.length}");

                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Center(
                        child: Text(
                          "No active dispatches yet.",
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      );
                    }

                    // 🔔 Show snackbar if new dispatch arrives
                    final count = snapshot.data!.docs.length;
                    if (_prevCount < count) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("🚨 New dispatch assigned!"),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      });
                    }
                    _prevCount = count;

                    final dispatches = snapshot.data!.docs;

                    return ListView.builder(
                      itemCount: dispatches.length,
                      itemBuilder: (context, index) {
                        final data =
                            dispatches[index].data() as Map<String, dynamic>;
                        final status = data["status"] ?? "Pending";

                        // ✅ Safely handle timestamp display
                        String formattedTime = "N/A";
                        if (data["timestamp"] is Timestamp) {
                          final ts = (data["timestamp"] as Timestamp).toDate();
                          formattedTime =
                              "${ts.year}-${ts.month}-${ts.day} ${ts.hour}:${ts.minute.toString().padLeft(2, '0')}";
                        }

                        final Color statusColor = status == "Resolved"
                            ? Colors.green
                            : status == "Dispatched"
                                ? Colors.orange
                                : Colors.redAccent;

                        return Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 4,
                          margin: const EdgeInsets.only(bottom: 16),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.local_fire_department,
                                  color: Color(0xFFA30000),
                                  size: 36,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        data["alertType"] ?? "Fire Alert",
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "Location: ${data["alertLocation"] ?? "Unknown"}",
                                        style: TextStyle(
                                            color: Colors.grey[700],
                                            fontSize: 14),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "Reported by: ${data["userReported"] ?? "N/A"}",
                                        style: TextStyle(
                                            color: Colors.grey[700],
                                            fontSize: 14),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "Responder: ${data["responderName"] ?? "Unknown"}",
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "Time: $formattedTime",
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 4,
                                          horizontal: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: statusColor.withOpacity(0.15),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          status,
                                          style: TextStyle(
                                            color: statusColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
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
}
