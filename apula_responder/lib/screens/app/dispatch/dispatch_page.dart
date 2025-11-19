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
  int _prevCount = 0;
  String searchQuery = "";
  DateTime? selectedDate;

  @override
  void initState() {
    super.initState();
    final email = FirebaseAuth.instance.currentUser?.email;
    print("📧 Logged in as: $email");
  }

  // 🔥 Modal Popup
  void _openDetailsModal(Map<String, dynamic> data) {
    final time = (data["timestamp"] as Timestamp).toDate();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Dispatch Details"),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("🔥 Alert: ${data['alertType']}"),
              Text("📍 Contact: ${data['userContact']}"),
              Text("🏠 Caller Address: ${data['userAddress'] ?? "Not Provided"}"),
              Text("👤 Reported By: ${data['userReported']}"),
              Text("📌 Status: ${data['status']}"),
              Text("🕒 Time: $time"),
              const SizedBox(height: 15),
              const Text("Responders:", style: TextStyle(fontWeight: FontWeight.bold)),
              ...((data["responders"] ?? []) as List)
                  .map((r) => Text("- ${r["name"]} (${r["email"]})")),
            ],
          ),
        ),
        actions: [
          TextButton(
            child: const Text("Close"),
            onPressed: () => Navigator.pop(context),
          )
        ],
      ),
    );
  }

  // 📅 Date Picker
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );

    if (picked != null) {
      setState(() => selectedDate = picked);
    }
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
              /// Back Button
              InkWell(
                onTap: () => Navigator.pop(context),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.chevron_left, size: 30),
                ),
              ),

              const SizedBox(height: 10),

              /// Title
              const Text(
                "Dispatches",
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),

              const SizedBox(height: 20),

              /// Search + Filter Row
              Row(
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
                      onChanged: (value) {
                        setState(() => searchQuery = value.toLowerCase());
                      },
                    ),
                  ),

                  const SizedBox(width: 10),

                  ElevatedButton.icon(
                    onPressed: _pickDate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                    ),
                    icon: const Icon(Icons.calendar_month, color: Colors.white),
                    label: const Text("Filter Date", style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              /// Table
              Expanded(
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

                    /// New Dispatch Notification
                    if (_prevCount < docs.length) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("🚨 New dispatch assigned!"),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      });
                    }
                    _prevCount = docs.length;

                    /// Search + Date Filter
                    final filtered = docs.where((d) {
                      final data = d.data() as Map<String, dynamic>;
                      final search = searchQuery;

                      final matchSearch =
                          data["alertType"].toString().toLowerCase().contains(search) ||
                          data["alertLocation"].toString().toLowerCase().contains(search) ||
                          data["userReported"].toString().toLowerCase().contains(search) ||
                          data["status"].toString().toLowerCase().contains(search);

                      if (selectedDate != null) {
                        final date = (data["timestamp"] as Timestamp).toDate();
                        final sameDay =
                            date.year == selectedDate!.year &&
                            date.month == selectedDate!.month &&
                            date.day == selectedDate!.day;
                        return matchSearch && sameDay;
                      }

                      return matchSearch;
                    }).toList();

                    if (filtered.isEmpty) {
                      return const Center(child: Text("No dispatch found."));
                    }

return Expanded(
  child: Scrollbar(
    thumbVisibility: true,
    child: SingleChildScrollView(
      scrollDirection: Axis.vertical, // 👈 vertical scroll
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal, // 👈 horizontal scroll
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: 1500, // prevents wide blank space
          ),
          child: DataTable(
            showCheckboxColumn: false,
            headingRowHeight: 45,
            dataRowHeight: 55,
            horizontalMargin: 12,
            columnSpacing: 20,

            columns: const [
              DataColumn(label: Text("Alert")),
              DataColumn(label: Text("Reporter")),
              DataColumn(label: Text("Contact")),
              DataColumn(label: Text("Address")),
              DataColumn(label: Text("Time")),
              DataColumn(label: Text("Status")),
            ],

           rows: filtered.map((doc) {
  final data = doc.data() as Map<String, dynamic>;
  final ts = (data["timestamp"] as Timestamp).toDate();

  final formattedTime =
      "${ts.year}-${ts.month.toString().padLeft(2, '0')}-"
      "${ts.day.toString().padLeft(2, '0')} "
      "${ts.hour.toString().padLeft(2, '0')}:"
      "${ts.minute.toString().padLeft(2, '0')}";

  Color statusColor =
      data["status"] == "Resolved" ? Colors.green : Colors.redAccent;

  return DataRow(
    onSelectChanged: (_) => _openDetailsModal(data),
    cells: [
      // ALERT
      DataCell(
        SizedBox(
          width: 150,
          child: Text(data["alertType"], overflow: TextOverflow.ellipsis),
        ),
      ),

      // REPORTER (✔ correct)
      DataCell(
        SizedBox(
          width: 120,
          child: Text(data["userReported"], overflow: TextOverflow.ellipsis),
        ),
      ),

      // CONTACT (✔ FIXED)
      DataCell(
        SizedBox(
          width: 120,
          child: Text(data["userContact"], overflow: TextOverflow.ellipsis),
        ),
      ),

      // ADDRESS
      DataCell(
        SizedBox(
          width: 220,
          child: Text(data["userAddress"] ?? "N/A",
              overflow: TextOverflow.ellipsis),
        ),
      ),

      // TIME
      DataCell(
        SizedBox(
          width: 170,
          child: Text(formattedTime, overflow: TextOverflow.ellipsis),
        ),
      ),

      // STATUS
      DataCell(
        SizedBox(
          width: 120,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              data["status"],
              textAlign: TextAlign.center,
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    ],
  );
}).toList(),

          ),
        ),
      ),
    ),
  ),
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