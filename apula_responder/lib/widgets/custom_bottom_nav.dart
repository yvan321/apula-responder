import 'package:flutter/material.dart';

class CustomBottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onItemTapped;
  final int notifCount;

  final GlobalKey? homeKey;
  final GlobalKey? dispatchKey;
  final GlobalKey? notificationsKey;
  final GlobalKey? settingsKey;

  const CustomBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onItemTapped,
    required this.notifCount,
    this.homeKey,
    this.dispatchKey,
    this.notificationsKey,
    this.settingsKey,
  });

  Widget _navIcon({
    required GlobalKey? keyTarget,
    required Widget icon,
  }) {
    return SizedBox(
      width: 28,
      height: 28,
      child: Center(
        child: Container(
          key: keyTarget,
          child: icon,
        ),
      ),
    );
  }

  Widget _notificationIcon({
    required GlobalKey? keyTarget,
    required bool active,
  }) {
    return SizedBox(
      width: 28,
      height: 28,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            key: keyTarget,
            child: Icon(
              active ? Icons.notifications : Icons.notifications_none,
            ),
          ),
          if (notifCount > 0)
            Positioned(
              right: -6,
              top: -4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Color(0xFFA30000),
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(
                  minWidth: 18,
                  minHeight: 18,
                ),
                child: Text(
                  notifCount > 9 ? "9+" : notifCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: selectedIndex,
      onTap: onItemTapped,
      backgroundColor: Colors.white,
      selectedItemColor: const Color(0xFFA30000),
      unselectedItemColor: Colors.grey,
      elevation: 8,
      items: [
        BottomNavigationBarItem(
          icon: _navIcon(
            keyTarget: homeKey,
            icon: const Icon(Icons.home_outlined),
          ),
          activeIcon: _navIcon(
            keyTarget: homeKey,
            icon: const Icon(Icons.home),
          ),
          label: "Home",
        ),
        BottomNavigationBarItem(
          icon: _navIcon(
            keyTarget: dispatchKey,
            icon: const Icon(Icons.local_fire_department_outlined),
          ),
          activeIcon: _navIcon(
            keyTarget: dispatchKey,
            icon: const Icon(Icons.local_fire_department),
          ),
          label: "Dispatch",
        ),
        BottomNavigationBarItem(
          icon: _notificationIcon(
            keyTarget: notificationsKey,
            active: false,
          ),
          activeIcon: _notificationIcon(
            keyTarget: notificationsKey,
            active: true,
          ),
          label: "Notifications",
        ),
        BottomNavigationBarItem(
          icon: _navIcon(
            keyTarget: settingsKey,
            icon: const Icon(Icons.settings_outlined),
          ),
          activeIcon: _navIcon(
            keyTarget: settingsKey,
            icon: const Icon(Icons.settings),
          ),
          label: "Settings",
        ),
      ],
    );
  }
}