// lib/screens/app/notifications/notification_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  String _filter = 'all'; // all, unread, read
  final Set<String> _selectedIds = {};
  bool _selectionMode = false;

  @override
  void initState() {
    super.initState();
    debugPrint("📨 Notifications loaded");
  }

  void _toggleSelection(String docId) {
    setState(() {
      if (_selectedIds.contains(docId)) {
        _selectedIds.remove(docId);
      } else {
        _selectedIds.add(docId);
      }

      if (_selectedIds.isEmpty) {
        _selectionMode = false;
      }
    });
  }

  void _startSelection(String docId) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(docId);
    });
  }

  void _clearSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _markSelectedAs(bool readValue) async {
    if (_selectedIds.isEmpty) return;

    try {
      final batch = FirebaseFirestore.instance.batch();

      for (final id in _selectedIds) {
        final ref = FirebaseFirestore.instance.collection('dispatches').doc(id);
        batch.update(ref, {'read': readValue});
      }

      await batch.commit();

      if (!mounted) return;
      _clearSelection();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            readValue
                ? "Selected notifications marked as read."
                : "Selected notifications marked as unread.",
          ),
        ),
      );
    } catch (e) {
      debugPrint("Batch mark read/unread error: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to update notifications: $e")),
      );
    }
  }

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

    final String status = data["status"]?.toString() ?? "N/A";
    final String alertType = data["alertType"]?.toString() ?? "N/A";
    final String reporter = data["userReported"]?.toString() ?? "N/A";
    final String contact = data["userContact"]?.toString() ?? "N/A";
    final String address = data["userAddress"]?.toString() ?? "N/A";
    final String dispatchType = _resolveDispatchType(data);

    final String formattedTimestamp =
        "${ts.year}-${ts.month.toString().padLeft(2, '0')}-${ts.day.toString().padLeft(2, '0')} "
        "${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}";

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
                        Icons.notifications_active_rounded,
                        color: Color(0xFFB71C1C),
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        "Notification Details",
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
                      icon: Icons.home_rounded,
                      label: "Address",
                      value: address,
                    ),
                    const SizedBox(height: 10),
                    _modernInfoCard(
                      icon: Icons.person_rounded,
                      label: "Reported By",
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
                      icon: Icons.access_time_rounded,
                      label: "Timestamp",
                      value: formattedTimestamp,
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
            const Icon(Icons.check, size: 18, color: Color(0xFFB71C1C)),
          if (selected) const SizedBox(width: 6),
          Text(label),
        ],
      ),
      selected: selected,
      onSelected: (_) => setState(() => _filter = value),
      selectedColor: const Color(0xFFFCECEA),
      backgroundColor: const Color(0xFFF2F2F7),
      labelStyle: TextStyle(
        color: selected ? const Color(0xFFB71C1C) : const Color(0xFF1C1C1E),
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _emptyState() {
    return const Center(child: Text("No notifications found."));
  }

  PreferredSizeWidget _buildSelectionAppBar() {
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: Colors.white,
      elevation: 0,
      title: Text(
        "${_selectedIds.length} selected",
        style: const TextStyle(
          color: Color(0xFF1C1C1E),
          fontWeight: FontWeight.bold,
        ),
      ),
      actions: [
        IconButton(
          tooltip: "Mark as read",
          onPressed: () => _markSelectedAs(true),
          icon: const Icon(Icons.mark_email_read_rounded),
          color: const Color(0xFF2E7D32),
        ),
        IconButton(
          tooltip: "Mark as unread",
          onPressed: () => _markSelectedAs(false),
          icon: const Icon(Icons.mark_email_unread_rounded),
          color: const Color(0xFFB71C1C),
        ),
        IconButton(
          tooltip: "Cancel",
          onPressed: _clearSelection,
          icon: const Icon(Icons.close_rounded),
          color: const Color(0xFF1C1C1E),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentEmail = FirebaseAuth.instance.currentUser?.email;

    return Scaffold(
      appBar: _selectionMode ? _buildSelectionAppBar() : null,
      body: SafeArea(
        child: Container(
          height: double.infinity,
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(20, _selectionMode ? 12 : 20, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_selectionMode) ...[
                const Text(
                  "Notifications",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFB71C1C),
                  ),
                ),
                const SizedBox(height: 16),
                _buildFilterChips(),
                const SizedBox(height: 16),
              ],
              Expanded(
                child: RefreshIndicator(
                  color: const Color(0xFFB71C1C),
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
                          final bool selected = _selectedIds.contains(doc.id);

                          return GestureDetector(
                            onLongPress: () {
                              if (!_selectionMode) {
                                _startSelection(doc.id);
                              }
                            },
                            onTap: () {
                              if (_selectionMode) {
                                _toggleSelection(doc.id);
                              } else {
                                _openDetailsModal(doc.id, data);
                              }
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 14),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: selected
                                    ? const Color(0xFFFFD7D7)
                                    : read
                                        ? const Color(0xFFE5E5EA)
                                        : const Color(0xFFB71C1C),
                                borderRadius: BorderRadius.circular(20),
                                border: selected
                                    ? Border.all(
                                        color: const Color(0xFFB71C1C),
                                        width: 2,
                                      )
                                    : null,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.08),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_selectionMode) ...[
                                    Padding(
                                      padding: const EdgeInsets.only(right: 10),
                                      child: Icon(
                                        selected
                                            ? Icons.check_circle
                                            : Icons.radio_button_unchecked,
                                        color: selected
                                            ? const Color(0xFFB71C1C)
                                            : const Color(0xFF8E8E93),
                                      ),
                                    ),
                                  ],
                                  Container(
                                    width: 46,
                                    height: 46,
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? Colors.white70
                                          : read
                                              ? const Color(0xFFD1D1D6)
                                              : Colors.white24,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(
                                      Icons.local_fire_department,
                                      size: 24,
                                      color: selected
                                          ? const Color(0xFFB71C1C)
                                          : read
                                              ? const Color(0xFFB71C1C)
                                              : Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
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
                                            color: selected
                                                ? const Color(0xFF1C1C1E)
                                                : read
                                                    ? const Color(0xFF1C1C1E)
                                                    : Colors.white,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          formatted,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: selected
                                                ? const Color(0xFF3A3A3C)
                                                : read
                                                    ? const Color(0xFF3A3A3C)
                                                    : Colors.white70,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          "Reporter: ${data["userReported"] ?? "Unknown"}",
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: selected
                                                ? const Color(0xFF3A3A3C)
                                                : read
                                                    ? const Color(0xFF3A3A3C)
                                                    : Colors.white70,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (!read && !_selectionMode)
                                    Container(
                                      width: 10,
                                      height: 10,
                                      margin: const EdgeInsets.only(left: 8, top: 4),
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
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