import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/accounting_provider.dart';
import '../providers/router_provider.dart';
import '../models/hotspot_user.dart';
import '../utils/app_theme.dart';
import 'dashboard_tab.dart';
import 'users_tab.dart';
import 'active_tab.dart';
import 'cards_tab.dart';
import 'login_screen.dart';
import 'settings_screen.dart';
import 'accounting_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  UserFilter _usersFilter = UserFilter.all;
  Timer? _accountingTimer;
  bool _syncingAccounting = false;
  bool? _accountingTrackerInstalled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncAccounting());
    _accountingTimer =
        Timer.periodic(const Duration(minutes: 1), (_) => _syncAccounting());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _syncAccounting();
  }

  Future<void> _syncAccounting() async {
    if (!mounted || _syncingAccounting) return;
    final RouterProvider router = context.read<RouterProvider>();
    final api = router.api;
    final config = router.config;
    if (api == null || config == null) return;
    _syncingAccounting = true;
    try {
      if (_accountingTrackerInstalled != true) {
        _accountingTrackerInstalled = await api.isFirstUseTrackerInstalled();
        if (_accountingTrackerInstalled != true) return;
      }
      final List<HotspotUser> users = await api.getUsers();
      if (!mounted) return;
      await context.read<AccountingProvider>().observeUsers(config, users);
    } catch (_) {
      // La contabilidad no interrumpe las pantallas ni la conexión existente.
    } finally {
      _syncingAccounting = false;
    }
  }

  @override
  void dispose() {
    _accountingTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _navigateTo(int index, {UserFilter? filter}) {
    setState(() {
      _currentIndex = index;
      if (filter != null) _usersFilter = filter;
    });
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<RouterProvider>();
    final auth = context.watch<AuthProvider>();
    final isVendor = auth.isVendor;
    final bool compact = MediaQuery.sizeOf(context).width < 420;

    // Vendor solo ve Tarjetas (index 3 del admin = index 0 del vendor)
    // Admin ve: Dashboard(0), Usuarios(1), Activos(2), Tarjetas(3), Contabilidad(4)
    // Vendor ve: solo Tarjetas
    final List<Widget> adminTabs = [
      DashboardTab(onNavigate: _navigateTo),
      UsersTab(
          key: ValueKey<UserFilter>(_usersFilter), initialFilter: _usersFilter),
      const ActiveTab(),
      const CardsTab(),
      AccountingTab(onRefresh: _syncAccounting),
    ];

    const List<BottomNavigationBarItem> adminNavItems = [
      BottomNavigationBarItem(
          icon: Icon(Icons.dashboard_rounded), label: 'Dashboard'),
      BottomNavigationBarItem(
          icon: Icon(Icons.people_rounded), label: 'Usuarios'),
      BottomNavigationBarItem(icon: Icon(Icons.wifi_rounded), label: 'Activos'),
      BottomNavigationBarItem(
          icon: Icon(Icons.card_membership_rounded), label: 'Tarjetas'),
      BottomNavigationBarItem(
          icon: Icon(Icons.account_balance_wallet_outlined),
          label: 'Contabilidad'),
    ];

    const List<Widget> vendorTabs = [CardsTab()];
    const List<BottomNavigationBarItem> vendorNavItems = [
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
          Tooltip(
            message: prov.config?.host ?? '',
            child: Container(
              margin: const EdgeInsets.only(right: 4),
              padding: EdgeInsets.symmetric(
                  horizontal: compact ? 6 : 10, vertical: 4),
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
                  if (!compact) ...[
                    const SizedBox(width: 6),
                    Text(
                      prov.config?.host ?? '',
                      style: const TextStyle(
                          color: AppTheme.success, fontSize: 12),
                    ),
                  ],
                ],
              ),
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
                onTap: (i) => setState(() {
                  _currentIndex = i;
                  // Desde la barra inferior Usuarios abre siempre en "Todos"
                  if (!isVendor && i == 1) _usersFilter = UserFilter.all;
                }),
                items: navItems,
              ),
            ),
    );
  }
}
