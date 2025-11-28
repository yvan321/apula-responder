// lib/screens/app/notifications/notification_page.dart
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
  String _filter = 'all'; // all, unread, read

  @override
  void initState() {
    super.initState();
    print("📨 Notifications loaded");
  }

  // ---------------------------
  // DETAILS MODAL + MARK READ
  // ---------------------------
  Future<void> _openDetailsModal(
    String docId,
    Map<String, dynamic> data,
  ) async {
    final ts = (data["timestamp"] as Timestamp).toDate();

    if (data['read'] != true) {
      try {
        await FirebaseFirestore.instance
            .collection('dispatches')
            .doc(docId)
            .update({'read': true});
      } catch (e) {
        debugPrint("Mark read error: $e");
      }
    }

    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(20),
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Notification Details",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),

                _info("Alert Type", data["alertType"]),
                _info("Location", data["alertLocation"]),
                _info("Address", data["userAddress"]),
                _info("Reported By", data["userReported"]),
                _info("Contact", data["userContact"]),

                const SizedBox(height: 12),
                const Text(
                  "Timestamp:",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(ts.toString()),

                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFA30000),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text("Close"),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _info(String title, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "$title: ",
            style: const TextStyle(
              color: Color(0xFFA30000),
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(child: Text(value?.toString() ?? "N/A")),
        ],
      ),
    );
  }

  // ---------------------------
  // FILTER CHIPS
  // ---------------------------
  Widget _buildFilterChips() {
    return Row(
      children: [
        _chip("All", 'all'),
        const SizedBox(width: 8),
        _chip("Unread", 'unread'),
        const SizedBox(width: 8),
        _chip("Read", 'read'),
      ],
    );
  }

  Widget _chip(String label, String value) {
    final selected = _filter == value;

    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selected)
            const Icon(Icons.check, size: 18, color: Color(0xFFA30000)),
          if (selected) const SizedBox(width: 6),
          Text(label),
        ],
      ),
      selected: selected,
      onSelected: (_) => setState(() => _filter = value),
      selectedColor: const Color(0xFFFCECEA),
      backgroundColor: Colors.grey.shade100,
      labelStyle: TextStyle(
        color: selected ? const Color(0xFFA30000) : Colors.black87,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  // ---------------------------
  // EMPTY PAGE LOTTIE
  // ---------------------------
  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Lottie.asset("assets/empty.json", height: 180),
          const SizedBox(height: 10),
          const Text(
            "No notifications yet.",
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // ---------------------------
  // MAIN UI
  // ---------------------------
  @override
  Widget build(BuildContext context) {
    final currentEmail = FirebaseAuth.instance.currentUser?.email;

    return Scaffold(
      body: SafeArea(
        child: Container(
          height: double.infinity, // ✅ FULL HEIGHT FIX
          width: double.infinity, // ✅ FULL WIDTH FIX
          padding: const EdgeInsets.all(20),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Notifications",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFA30000),
                ),
              ),

              const SizedBox(height: 16),
              _buildFilterChips(),
              const SizedBox(height: 16),

              // LIST (takes remaining space)
              Expanded(
                child: RefreshIndicator(
                  color: const Color(0xFFA30000),
                  backgroundColor: Colors.white,
                  onRefresh: () async {
                    await Future.delayed(const Duration(milliseconds: 300));
                    setState(() {});
                  },

                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('dispatches')
                        .where('responderEmails', arrayContains: currentEmail)
                        .orderBy('timestamp', descending: true)
                        .snapshots(),

                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final docs = snapshot.data!.docs;
                      if (docs.isEmpty) return _emptyState();

                      final filtered = docs.where((d) {
                        final data = d.data() as Map<String, dynamic>;
                        final read = data['read'] == true;

                        if (_filter == 'unread') return !read;
                        if (_filter == 'read') return read;
                        return true;
                      }).toList();

                      if (filtered.isEmpty) {
                        return const Center(
                          child: Text(
                            "No results.",
                            style: TextStyle(color: Colors.grey),
                          ),
                        );
                      }

                      return ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final doc = filtered[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final ts = (data["timestamp"] as Timestamp).toDate();

                          final formatted =
                              "${ts.year}-${ts.month.toString().padLeft(2, '0')}-${ts.day.toString().padLeft(2, '0')} "
                              "${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}";

                          final bool read = data["read"] == true;

                          return GestureDetector(
                            onTap: () => _openDetailsModal(doc.id, data),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 14),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: read
                                    ? Theme.of(context).cardColor
                                    : const Color(0xFFA30000),
                                borderRadius: BorderRadius.circular(12),
                                border: read
                                    ? Border.all(
                                        color: const Color(0xFFA30000),
                                        width: 1.4,
                                      )
                                    : null,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.08),
                                    blurRadius: 6,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),

                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // ICON BUBBLE
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: read
                                          ? const Color(
                                              0xFFA30000,
                                            ).withOpacity(0.15)
                                          : Colors.white24,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.local_fire_department,
                                      size: 26,
                                      color: read
                                          ? const Color(0xFFA30000)
                                          : Colors.white,
                                    ),
                                  ),

                                  const SizedBox(width: 14),

                                  // TEXTS
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          (data["alertType"] ?? "FIRE ALERT")
                                              .toString()
                                              .toUpperCase(),
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            color: read
                                                ? const Color(0xFFA30000)
                                                : Colors.white,
                                          ),
                                        ),

                                        const SizedBox(height: 4),

                                        Text(
                                          formatted,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: read
                                                ? Colors.grey.shade700
                                                : Colors.white70,
                                          ),
                                        ),

                                        const SizedBox(height: 6),

                                        Text(
                                          "Reporter: ${data["userReported"] ?? "Unknown"}",
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: read
                                                ? Colors.black87
                                                : Colors.white70,
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
