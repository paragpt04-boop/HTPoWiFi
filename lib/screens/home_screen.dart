import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/router_provider.dart';
import '../utils/app_theme.dart';
import 'dashboard_tab.dart';
import 'users_tab.dart';
import 'active_tab.dart';
import 'cards_tab.dart';
import 'login_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  void _navigateTo(int index) {
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<RouterProvider>();
    final auth = context.watch<AuthProvider>();
    final isVendor = auth.isVendor;

    // Vendor solo ve Tarjetas (index 3 del admin = index 0 del vendor)
    // Admin ve: Dashboard(0), Usuarios(1), Activos(2), Tarjetas(3)
    // Vendor ve: solo Tarjetas
    final List<Widget> adminTabs = [
      DashboardTab(onNavigate: _navigateTo),
      const UsersTab(),
      const ActiveTab(),
      const CardsTab(),
    ];

    final List<BottomNavigationBarItem> adminNavItems = const [
      BottomNavigationBarItem(
          icon: Icon(Icons.dashboard_rounded), label: 'Dashboard'),
      BottomNavigationBarItem(
          icon: Icon(Icons.people_rounded), label: 'Usuarios'),
      BottomNavigationBarItem(
          icon: Icon(Icons.wifi_rounded), label: 'Activos'),
      BottomNavigationBarItem(
          icon: Icon(Icons.card_membership_rounded), label: 'Tarjetas'),
    ];

    final List<Widget> vendorTabs = const [CardsTab()];
    final List<BottomNavigationBarItem> vendorNavItems = const [
      BottomNavigationBarItem(
          icon: Icon(Icons.card_membership_rounded), label: 'Tarjetas'),
    ];

    final tabs = isVendor ? vendorTabs : adminTabs;
    final navItems = isVendor ? vendorNavItems : adminNavItems;

    // Si el índice actual está fuera de rango al cambiar rol, resetear
    final safeIndex = _currentIndex.clamp(0, tabs.length - 1);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_tethering, color: AppTheme.primary, size: 22),
            const SizedBox(width: 8),
            const Text('HTPoWiFi',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            if (isVendor) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('VENDEDOR',
                    style: TextStyle(
                        color: AppTheme.accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8)),
              ),
            ],
          ],
        ),
        actions: [
          // Connection chip
          Container(
            margin: const EdgeInsets.only(right: 4),
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
          // Settings (solo Admin)
          if (!isVendor)
            IconButton(
              icon: const Icon(Icons.settings_rounded, size: 22),
              tooltip: 'Configuración',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
          // Logout
          IconButton(
            icon: const Icon(Icons.logout, size: 20),
            tooltip: 'Desconectar',
            onPressed: () {
              prov.disconnect();
              auth.logout();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
        ],
      ),
      body: tabs[safeIndex],
      bottomNavigationBar: navItems.length == 1
          ? null
          : Container(
              decoration: const BoxDecoration(
                border: Border(
                    top: BorderSide(color: AppTheme.divider, width: 0.5)),
              ),
              child: BottomNavigationBar(
                currentIndex: safeIndex,
                onTap: (i) => setState(() => _currentIndex = i),
                items: navItems,
              ),
            ),
    );
  }
}
