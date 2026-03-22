// lib/screens/app/dispatch/dispatch_page.dart

import 'dart:convert';

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
  final TextEditingController _searchController = TextEditingController();

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

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _resetFilters() {
    _searchController.clear();

    setState(() {
      selectedDate = null;
      searchQuery = "";
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );

    if (picked != null) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  String _resolveDispatchType(Map<String, dynamic> data) {
    final String explicitType =
        (data["dispatchType"] ??
                data["dispatch_type"] ??
                data["requestType"] ??
                data["typeOfDispatch"] ??
                "")
            .toString()
            .trim()
            .toLowerCase();

    if (explicitType.isNotEmpty) {
      if (explicitType.contains("backup")) return "Backup";
      if (explicitType.contains("primary")) return "Primary";
    }

    final sourceDispatchId = (data["sourceDispatchId"] ?? "").toString().trim();
    if (sourceDispatchId.isNotEmpty) return "Backup";

    final approvedFromBackup =
        (data["approvedFromBackupRequest"] ?? false) == true;
    if (approvedFromBackup) return "Backup";

    final requestedWaveNumber = data["requestedWaveNumber"];
    if (requestedWaveNumber != null) {
      final int wave = requestedWaveNumber is int
          ? requestedWaveNumber
          : int.tryParse(requestedWaveNumber.toString()) ?? 1;
      if (wave > 1) return "Backup";
    }

    final waveNumber = data["waveNumber"];
    if (waveNumber != null) {
      final int wave = waveNumber is int
          ? waveNumber
          : int.tryParse(waveNumber.toString()) ?? 1;
      if (wave > 1) return "Backup";
    }

    return "Primary";
  }

  Widget _buildDispatchSnapshotImage(dynamic snapshotUrl) {
    final fallback = Container(
      height: 210,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFE5E5EA),
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Center(
        child: Icon(
          Icons.broken_image_rounded,
          size: 40,
          color: Color(0xFF8E8E93),
        ),
      ),
    );

    if (snapshotUrl == null) return fallback;

    String value = snapshotUrl.toString().trim();
    if (value.isEmpty) return fallback;

    try {
      if (value.startsWith('http://') || value.startsWith('https://')) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Image.network(
            value,
            height: 210,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => fallback,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Container(
                height: 210,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E5EA),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Center(child: CircularProgressIndicator()),
              );
            },
          ),
        );
      }

      if (value.startsWith('data:image')) {
        final commaIndex = value.indexOf(',');
        if (commaIndex == -1) return fallback;
        value = value.substring(commaIndex + 1).trim();
      }

      value = value.replaceAll(RegExp(r'\s+'), '');
      final bytes = base64Decode(value);

      return ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Image.memory(
          bytes,
          height: 210,
          width: double.infinity,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => fallback,
        ),
      );
    } catch (e) {
      debugPrint("Dispatch modal image decode error: $e");
      return fallback;
    }
  }

  Widget _modernInfoCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFF2F2F7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: const Color(0xFFB71C1C),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF1C1C1E),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openDetailsModal(Map<String, dynamic> data) {
    final ts = (data["timestamp"] as Timestamp).toDate();

    final String status = data["status"]?.toString() ?? "N/A";
    final String alertType = data["alertType"]?.toString() ?? "N/A";
    final String reporter = data["userReported"]?.toString() ?? "N/A";
    final String contact = data["userContact"]?.toString() ?? "N/A";
    final String address = data["userAddress"]?.toString() ?? "N/A";
    final String dispatchType = _resolveDispatchType(data);

    final String formattedTimestamp =
        "${ts.year}-${ts.month.toString().padLeft(2, '0')}-${ts.day.toString().padLeft(2, '0')} "
        "${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}";

    final snapshotUrl =
        data["snapshotUrl"] ??
        data["snapshotBase64"] ??
        data["imageBase64"] ??
        data["photo"];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.78,
        minChildSize: 0.55,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, controller) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF7F7FA),
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5E5EA),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.local_fire_department,
                        color: Color(0xFFB71C1C),
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        "Dispatch Details",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1C1C1E),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                      color: const Color(0xFF1C1C1E),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  children: [
                    if (snapshotUrl != null &&
                        snapshotUrl.toString().trim().isNotEmpty) ...[
                      _buildDispatchSnapshotImage(snapshotUrl),
                      const SizedBox(height: 14),
                    ],
                    _modernInfoCard(
                      icon: Icons.flag_rounded,
                      label: "Status",
                      value: status,
                    ),
                    const SizedBox(height: 10),
                    _modernInfoCard(
                      icon: Icons.warning_amber_rounded,
                      label: "Alert Type",
                      value: alertType,
                    ),
                    const SizedBox(height: 10),
                    _modernInfoCard(
                      icon: Icons.swap_horiz_rounded,
                      label: "Dispatch Type",
                      value: dispatchType,
                    ),
                    const SizedBox(height: 10),
                    _modernInfoCard(
                      icon: Icons.person_rounded,
                      label: "Reporter",
                      value: reporter,
                    ),
                    const SizedBox(height: 10),
                    _modernInfoCard(
                      icon: Icons.phone_rounded,
                      label: "Contact",
                      value: contact,
                    ),
                    const SizedBox(height: 10),
                    _modernInfoCard(
                      icon: Icons.home_rounded,
                      label: "Address",
                      value: address,
                    ),
                    const SizedBox(height: 10),
                    _modernInfoCard(
                      icon: Icons.access_time_rounded,
                      label: "Timestamp",
                      value: formattedTimestamp,
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Responders",
                            style: TextStyle(
                              color: Color(0xFF1C1C1E),
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ...((data["responders"] ?? []) as List).map<Widget>((
                            r,
                          ) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF2F2F7),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFD1D1D6),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.person,
                                      size: 20,
                                      color: Color(0xFFB71C1C),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      "${r["name"] ?? "Unknown"} (${r["email"] ?? "No email"})",
                                      style: const TextStyle(
                                        color: Color(0xFF1C1C1E),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 10,
                      offset: Offset(0, -2),
                    ),
                  ],
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: const Color(0xFFE5E5EA),
                      foregroundColor: const Color(0xFF1C1C1E),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      "Close",
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: "Search...",
                    hintStyle: const TextStyle(color: Color(0xFF8D6E63)),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: Color(0xFF8D6E63),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: Color(0xFFD7CCC8),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: Color(0xFFFF8A65),
                        width: 1.4,
                      ),
                    ),
                  ),
                  onChanged: (v) {
                    setState(() {
                      searchQuery = v.toLowerCase();
                    });
                  },
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_month),
                label: Text(selectedDate == null ? "Filter" : "Filtered"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFE0B2),
                  foregroundColor: const Color(0xFF8D4E00),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              if (selectedDate != null || searchQuery.isNotEmpty) ...[
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _resetFilters,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE5E5EA),
                    foregroundColor: const Color(0xFF1C1C1E),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text("Clear"),
                ),
              ],
            ],
          ),
          if (selectedDate != null) ...[
            const SizedBox(height: 8),
            Text(
              "Filtered date: ${selectedDate!.year}-${selectedDate!.month.toString().padLeft(2, '0')}-${selectedDate!.day.toString().padLeft(2, '0')}",
              style: const TextStyle(
                color: Color(0xFF6D4C41),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<QueryDocumentSnapshot> _filterDocs(List<QueryDocumentSnapshot> docs) {
    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final s = searchQuery;

      final String reporter =
          data["userReported"]?.toString().toLowerCase() ?? "";
      final String status = data["status"]?.toString().toLowerCase() ?? "";
      final String address = data["userAddress"]?.toString().toLowerCase() ?? "";
      final String alertType =
          data["alertType"]?.toString().toLowerCase() ?? "";
      final String contact =
          data["userContact"]?.toString().toLowerCase() ?? "";
      final String dispatchType =
          _resolveDispatchType(data).toLowerCase();

      final DateTime ts = (data["timestamp"] as Timestamp).toDate();
      final String timestampFormatted =
          "${ts.year}-${ts.month.toString().padLeft(2, '0')}-${ts.day.toString().padLeft(2, '0')} "
          "${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}";

      final bool matches =
          reporter.contains(s) ||
          status.contains(s) ||
          address.contains(s) ||
          alertType.contains(s) ||
          contact.contains(s) ||
          dispatchType.contains(s) ||
          timestampFormatted.contains(s);

      if (selectedDate != null) {
        return ts.year == selectedDate!.year &&
            ts.month == selectedDate!.month &&
            ts.day == selectedDate!.day &&
            matches;
      }

      return matches;
    }).toList();
  }

  Widget _buildDispatchCard(Map<String, dynamic> data) {
    final ts = (data["timestamp"] as Timestamp).toDate();
    final formatted =
        "${ts.year}-${ts.month.toString().padLeft(2, '0')}-${ts.day.toString().padLeft(2, '0')} "
        "${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}";

    final bool statusResolved = data["status"] == "Resolved";

    return GestureDetector(
      onTap: () => _openDetailsModal(data),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFE5E5EA),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    formatted,
                    style: const TextStyle(
                      color: Color(0xFF1C1C1E),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: statusResolved
                          ? const [
                              Color(0xFF43A047),
                              Color(0xFF66BB6A),
                            ]
                          : const [
                              Color(0xFFD32F2F),
                              Color(0xFFFF7043),
                            ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    data["status"]?.toString() ?? "N/A",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              data["userAddress"]?.toString() ?? "Unknown Address",
              style: const TextStyle(
                color: Color(0xFF3A3A3C),
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentEmail = FirebaseAuth.instance.currentUser?.email;

    return Scaffold(
      floatingActionButton: _showBackToTop
          ? Padding(
              padding: EdgeInsets.only(right: fabRight, bottom: fabBottom),
              child: FloatingActionButton(
                backgroundColor: const Color(0xFFB71C1C),
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
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Text(
                "Dispatches",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFB71C1C),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _buildTopBar(),
            const SizedBox(height: 10),
            Expanded(
              child: RefreshIndicator(
                color: const Color(0xFFB71C1C),
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
                    final filtered = _filterDocs(docs);

                    if (filtered.isEmpty) {
                      return ListView(
                        controller: _scrollController,
                        children: const [
                          SizedBox(height: 120),
                          Center(child: Text("No dispatch found.")),
                        ],
                      );
                    }

                    return SingleChildScrollView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
                      child: Column(
                        children: filtered.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return _buildDispatchCard(data);
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