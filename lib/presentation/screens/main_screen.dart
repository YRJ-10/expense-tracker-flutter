
import 'package:flutter/material.dart';
import 'package:expense_tracker_flutter/presentation/screens/dashboard/dashboard_screen.dart';
import 'package:expense_tracker_flutter/presentation/screens/history/history_screen.dart';
import 'package:expense_tracker_flutter/presentation/screens/analytics/analytics_screen.dart';
import 'package:expense_tracker_flutter/presentation/screens/profile/profile_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  @override
  void initState() {
    super.initState();
  }

  void _navigateToTab(int index) {
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      DashboardScreen(key: UniqueKey(), onNavigateToHistory: () => _navigateToTab(1)),
      const HistoryScreen(),
      const AnalyticsScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      body: screens[_currentIndex],
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.pushNamed(context, '/add-transaction');
          if (_currentIndex == 0) {
            setState(() => _currentIndex = 1);
            await Future.delayed(const Duration(milliseconds: 100));
            setState(() => _currentIndex = 0);
          }
        },
        backgroundColor: const Color(0xFF6C63FF),
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: const Color(0xFF1A1A2E),
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        padding: EdgeInsets.zero,
        height: 64,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _navItem(Icons.dashboard_outlined, Icons.dashboard, 'Dashboard', 0),
            _navItem(Icons.receipt_long_outlined, Icons.receipt_long, 'Riwayat', 1),
            const SizedBox(width: 48),
            _navItem(Icons.bar_chart_outlined, Icons.bar_chart, 'Analitik', 2),
            _navItem(Icons.person_outlined, Icons.person, 'Profil', 3),
          ],
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, IconData activeIcon, String label, int index) {
    final isActive = _currentIndex == index;
    return InkWell(
      onTap: () => setState(() => _currentIndex = index),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              color: isActive ? const Color(0xFF6C63FF) : Colors.white38,
              size: 22,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isActive ? const Color(0xFF6C63FF) : Colors.white38,
                fontSize: 10,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}