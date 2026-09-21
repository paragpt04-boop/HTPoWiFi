import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/router_provider.dart';
import '../services/mikrotik_api.dart';
import '../utils/app_theme.dart';

class DashboardTab extends StatefulWidget {
  /// Callback para navegar a otra pestaña del HomeScreen.
  /// índices: 0=Dashboard, 1=Usuarios, 2=Activos, 3=Tarjetas
  final ValueChanged<int>? onNavigate;

  const DashboardTab({super.key, this.onNavigate});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  Map<String, int> _stats = {};
  Map<String, dynamic> _sysInfo = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final api = context.read<RouterProvider>().api;
    if (api == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final stats = await api.getStats();
      final info = await api.getSystemInfo();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _sysInfo = info;
        _loading = false;
      });
    } on MikroTikException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message),
        backgroundColor: AppTheme.error,
        duration: const Duration(seconds: 6),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.primary));
    }
    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Router info card
          _buildRouterInfoCard(),
          const SizedBox(height: 16),
          // Stats grid — cada tile es navegable
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.people,
                  label: 'Total Usuarios',
                  value: '${_stats['totalUsers'] ?? 0}',
                  color: AppTheme.primary,
                  onTap: () => widget.onNavigate?.call(1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.wifi,
                  label: 'Conectados',
                  value: '${_stats['activeNow'] ?? 0}',
                  color: AppTheme.success,
                  onTap: () => widget.onNavigate?.call(2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.check_circle,
                  label: 'Disponibles',
                  value: '${_stats['available'] ?? 0}',
                  color: AppTheme.accent,
                  onTap: () => widget.onNavigate?.call(1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.timer_off,
                  label: 'Expirados',
                  value: '${_stats['expired'] ?? 0}',
                  color: AppTheme.warning,
                  onTap: () => widget.onNavigate?.call(1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Quick actions
          const Text('Acciones rápidas',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _QuickAction(
                icon: Icons.person_add,
                label: 'Ver Usuarios',
                onTap: () => widget.onNavigate?.call(1),
              ),
              _QuickAction(
                icon: Icons.wifi,
                label: 'Sesiones Activas',
                onTap: () => widget.onNavigate?.call(2),
              ),
              _QuickAction(
                icon: Icons.card_membership,
                label: 'Tarjetas',
                onTap: () => widget.onNavigate?.call(3),
              ),
              _QuickAction(
                icon: Icons.refresh,
                label: 'Actualizar',
                onTap: _refresh,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRouterInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withOpacity(0.15),
            AppTheme.card,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.router, color: AppTheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                _sysInfo['identity']?.toString() ?? 'MikroTik',
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.success.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'v${_sysInfo['version'] ?? '?'}',
                  style:
                      const TextStyle(color: AppTheme.success, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _infoRow('Modelo', _sysInfo['board']?.toString() ?? '-'),
          _infoRow('Uptime', _sysInfo['uptime']?.toString() ?? '-'),
          _infoRow('CPU', '${_sysInfo['cpu-load'] ?? '-'}%'),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Text('$label: ',
              style:
                  const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          Text(value,
              style:
                  const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.divider, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, color: color, size: 24),
                  if (onTap != null)
                    Icon(Icons.arrow_forward_ios,
                        color: color.withOpacity(0.5), size: 12),
                ],
              ),
              const SizedBox(height: 10),
              Text(value,
                  style: TextStyle(
                      color: color,
                      fontSize: 28,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(label,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.cardLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppTheme.primary, size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
