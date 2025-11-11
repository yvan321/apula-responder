import 'package:flutter/material.dart';

class DispatchPage extends StatefulWidget {
  final List<String> devices;

  const DispatchPage({super.key, required this.devices});

  @override
  State<DispatchPage> createState() => _DispatchPageState();
}

class _DispatchPageState extends State<DispatchPage> {
  int _selectedIndex = 1; // 📍 'Dispatch' tab selected by default

  // ✅ Mock dispatch data
  final List<Map<String, String>> mockDispatches = [
    {
      "title": "Residential Fire - Molino 3",
      "status": "En Route",
      "location": "Molino Blvd, Bacoor City",
      "time": "2 mins ago",
      "team": "Alpha Team 2",
    },
    {
      "title": "Warehouse Fire - Niog",
      "status": "On Scene",
      "location": "Niog 4, Bacoor City",
      "time": "8 mins ago",
      "team": "Bravo Team 1",
    },
    {
      "title": "Vehicle Fire - Talaba",
      "status": "Resolved",
      "location": "Talaba Bridge, Bacoor City",
      "time": "25 mins ago",
      "team": "Charlie Unit 3",
    },
  ];


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 🧭 Bottom Navigation Bar

      // 📱 Main Body
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🔙 Custom Back Button
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
                "Dispatch",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),

              // 🚒 Dispatch List
              Expanded(child: _buildDispatchList(context)),
            ],
          ),
        ),
      ),
    );
  }

  /// 🧱 Mock Dispatch List
  Widget _buildDispatchList(BuildContext context) {
    return ListView.builder(
      itemCount: mockDispatches.length,
      itemBuilder: (context, index) {
        final dispatch = mockDispatches[index];
        final status = dispatch["status"] ?? "";
        final Color statusColor = status == "Resolved"
            ? Colors.green
            : status == "En Route"
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
                  Icons.fire_truck,
                  color: Color(0xFFA30000),
                  size: 36,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dispatch["title"] ?? "",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dispatch["location"] ?? "",
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            dispatch["team"] ?? "",
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            dispatch["time"] ?? "",
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 10,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
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
  }
}
