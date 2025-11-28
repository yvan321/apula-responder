import 'package:flutter/material.dart';

class CustomBottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onItemTapped;

  final int notifCount; // 🔥 UNREAD NOTIF COUNTER

  const CustomBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onItemTapped,
    required this.notifCount,
  });

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: selectedIndex,
      onTap: onItemTapped,
      backgroundColor: Colors.white,
      selectedItemColor: const Color(0xFFA30000), // Active red
      unselectedItemColor: Colors.grey,
      elevation: 12,
      items: [
        const BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          activeIcon: Icon(Icons.home),
          label: "Home",
        ),

        const BottomNavigationBarItem(
          icon: Icon(Icons.local_fire_department_outlined),
          activeIcon: Icon(Icons.local_fire_department),
          label: "Dispatch",
        ),

        // 🔥 NOTIFICATION WITH BADGE
        BottomNavigationBarItem(
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications_none),

              if (notifCount > 0)
                Positioned(
                  right: -6,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Color(0xFFA30000),
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 20,
                      minHeight: 20,
                    ),
                    child: Text(
                      notifCount > 9 ? "9+" : notifCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          activeIcon: const Icon(Icons.notifications),
          label: "Notifications",
        ),

        const BottomNavigationBarItem(
          icon: Icon(Icons.settings_outlined),
          activeIcon: Icon(Icons.settings),
          label: "Settings",
        ),
      ],
    );
  }
}
