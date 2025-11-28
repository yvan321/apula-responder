// lib/screens/app/dispatch/dispatch_page.dart
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
  String searchQuery = "";
  DateTime? selectedDate;

  final ScrollController _scrollController = ScrollController();
  bool _showBackToTop = false;

  double fabBottom = 25;
  double fabRight = 16;

  @override
  void initState() {
    super.initState();

    _scrollController.addListener(() {
      if (_scrollController.offset > 300 && !_showBackToTop) {
        setState(() => _showBackToTop = true);
      } else if (_scrollController.offset <= 300 && _showBackToTop) {
        setState(() => _showBackToTop = false);
      }
    });
  }

  // -------------------------------------------------------------------
  // POPUP MODAL
  // -------------------------------------------------------------------
  void _openDetailsModal(Map<String, dynamic> data) {
    final ts = (data["timestamp"] as Timestamp).toDate();

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
                  "Dispatch Details",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 16),
                _info("Status", data["status"]),
                _info("Alert Type", data["alertType"] ?? "N/A"),
                _info("Location", data["alertLocation"] ?? "N/A"),
                _info("Reporter", data["userReported"] ?? "N/A"),
                _info("Contact", data["userContact"] ?? "N/A"),
                _info("Address", data["userAddress"] ?? "N/A"),

                const SizedBox(height: 8),
                _info("Timestamp", ts.toString()),

                const SizedBox(height: 14),
                const Text(
                  "Responders:",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 6),

                ...(data["responders"] ?? []).map<Widget>(
                  (r) => Text("- ${r["name"]} (${r["email"]})"),
                ),

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
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Close"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _info(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "$label: ",
            style: const TextStyle(
              color: Color(0xFFA30000),
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // DATE PICKER
  // -------------------------------------------------------------------
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => selectedDate = picked);
  }

  // -------------------------------------------------------------------
  // MAIN UI
  // -------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final currentEmail = FirebaseAuth.instance.currentUser?.email;

    return Scaffold(
      floatingActionButton: _showBackToTop
          ? Padding(
              padding: EdgeInsets.only(right: fabRight, bottom: fabBottom),
              child: FloatingActionButton(
                backgroundColor: const Color(0xFFA30000),
                child: const Icon(Icons.arrow_upward, color: Colors.white),
                onPressed: () {
                  _scrollController.animateTo(
                    0,
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOut,
                  );
                },
              ),
            )
          : null,

      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // TITLE
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Text(
                "Dispatches",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFA30000),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // SEARCH + FILTER
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: "Search...",
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onChanged: (v) =>
                          setState(() => searchQuery = v.toLowerCase()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_month),
                    label: const Text("Filter"),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // -------------------------------------------------------------------
            // MAIN LIST WITH PULL TO REFRESH
            // -------------------------------------------------------------------
            Expanded(
              child: RefreshIndicator(
                color: const Color(0xFFA30000),
                backgroundColor: Colors.white,
                strokeWidth: 2.5,
                triggerMode: RefreshIndicatorTriggerMode.anywhere,
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

                    // Filtering logic
                    final filtered = docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final s = searchQuery;

                      final String reporter =
                          data["userReported"]?.toString().toLowerCase() ?? "";
                      final String status =
                          data["status"]?.toString().toLowerCase() ?? "";
                      final String address =
                          data["userAddress"]?.toString().toLowerCase() ?? "";
                      final String location =
                          data["alertLocation"]?.toString().toLowerCase() ?? "";
                      final String alertType =
                          data["alertType"]?.toString().toLowerCase() ?? "";
                      final String contact =
                          data["userContact"]?.toString().toLowerCase() ?? "";

                      final DateTime ts =
                          (data["timestamp"] as Timestamp).toDate();
                      final String timestampFormatted =
                          "${ts.year}-${ts.month.toString().padLeft(2, '0')}-${ts.day.toString().padLeft(2, '0')} "
                          "${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}";

                      final matches =
                          reporter.contains(s) ||
                          status.contains(s) ||
                          address.contains(s) ||
                          location.contains(s) ||
                          alertType.contains(s) ||
                          contact.contains(s) ||
                          timestampFormatted.contains(s);

                      if (selectedDate != null) {
                        return ts.year == selectedDate!.year &&
                            ts.month == selectedDate!.month &&
                            ts.day == selectedDate!.day &&
                            matches;
                      }

                      return matches;
                    }).toList();

                    if (filtered.isEmpty) {
                      return const Center(child: Text("No dispatch found."));
                    }

                    return SingleChildScrollView(
                      controller: _scrollController,
                      padding:
                          const EdgeInsets.fromLTRB(20, 10, 20, 30),
                      child: Column(
                        children: filtered.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final ts =
                              (data["timestamp"] as Timestamp).toDate();

                          final formatted =
                              "${ts.year}-${ts.month.toString().padLeft(2, '0')}-${ts.day.toString().padLeft(2, '0')} "
                              "${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}";

                          final statusResolved =
                              data["status"] == "Resolved";

                          return GestureDetector(
                            onTap: () => _openDetailsModal(data),
                            child: Container(
                              margin:
                                  const EdgeInsets.only(bottom: 14),
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Colors.red, Colors.orange],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius:
                                    BorderRadius.circular(16),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 6,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        formatted,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets
                                            .symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: statusResolved
                                              ? Colors.green
                                              : Colors.redAccent,
                                          borderRadius:
                                              BorderRadius.circular(
                                                  20),
                                        ),
                                        child: Text(
                                          data["status"],
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight:
                                                FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    data["userAddress"] ??
                                        "Unknown Address",
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
