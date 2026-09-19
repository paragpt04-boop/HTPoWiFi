import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/router_provider.dart';
import '../utils/app_theme.dart';
import 'dashboard_tab.dart';
import 'users_tab.dart';
import 'active_tab.dart';
import 'cards_tab.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final _tabs = const [
    DashboardTab(),
    UsersTab(),
    ActiveTab(),
    CardsTab(),
  ];

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<RouterProvider>();
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_tethering, color: AppTheme.primary, size: 22),
            const SizedBox(width: 8),
            const Text('HTPoWiFi',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        actions: [
          // Connection indicator
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.success.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppTheme.success,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  prov.config?.host ?? '',
                  style:
                      const TextStyle(color: AppTheme.success, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout, size: 20),
            tooltip: 'Desconectar',
            onPressed: () {
              prov.disconnect();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
        ],
      ),
      body: _tabs[_currentIndex],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppTheme.divider, width: 0.5)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (i) => setState(() => _currentIndex = i),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_rounded),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.people_rounded),
              label: 'Usuarios',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.wifi_rounded),
              label: 'Activos',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.card_membership_rounded),
              label: 'Tarjetas',
            ),
          ],
        ),
      ),
    );
  }
}
