import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  late AppLinks _appLinks;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();
    _appLinks.uriLinkStream.listen((uri) async {
      await Supabase.instance.client.auth.getSessionFromUrl(uri);
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    });
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
        child: const Icon(Icons.add, color: Colors.white),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: const Color(0xFF1A1A2E),
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              color: isActive ? const Color(0xFF6C63FF) : Colors.white38,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive ? const Color(0xFF6C63FF) : Colors.white38,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}