import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'ledger_screen.dart';
import 'people_screen.dart';
import 'stats_screen.dart';

/// 하단 탭 4개: 홈 · 사람 · 장부 · 통계
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _screens = [
    HomeScreen(),
    PeopleScreen(),
    LedgerScreen(),
    StatsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined, size: 28),
              selectedIcon: Icon(Icons.home, size: 28),
              label: '홈'),
          NavigationDestination(
              icon: Icon(Icons.people_outline, size: 28),
              selectedIcon: Icon(Icons.people, size: 28),
              label: '사람'),
          NavigationDestination(
              icon: Icon(Icons.menu_book_outlined, size: 28),
              selectedIcon: Icon(Icons.menu_book, size: 28),
              label: '장부'),
          NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined, size: 28),
              selectedIcon: Icon(Icons.bar_chart, size: 28),
              label: '통계'),
        ],
      ),
    );
  }
}
