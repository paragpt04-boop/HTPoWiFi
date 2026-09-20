import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/active_session.dart';
import '../providers/router_provider.dart';
import '../services/mikrotik_api.dart';
import '../utils/app_theme.dart';

class ActiveTab extends StatefulWidget {
  const ActiveTab({super.key});

  @override
  State<ActiveTab> createState() => _ActiveTabState();
}

class _ActiveTabState extends State<ActiveTab> {
  List<ActiveSession> _sessions = [];
  bool _loading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  Future<void> _load() async {
    final api = context.read<RouterProvider>().api;
    if (api == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final sessions = await api.getActiveSessions();
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _loading = false;
      });
    } on MikroTikException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack(e.message, isError: true);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppTheme.error : AppTheme.success,
      duration: Duration(seconds: isError ? 6 : 2),
    ));
  }

  Future<void> _disconnect(ActiveSession session) async {
    if (session.id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: const Text('Desconectar',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('Desconectar a "${session.user}"?',
            style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Desconectar',
                  style: TextStyle(color: AppTheme.error))),
        ],
      ),
    );
    if (confirm == true) {
      final api = context.read<RouterProvider>().api;
      if (api == null) return;
      try {
        await api.disconnectSession(session.id!);
        _snack('Usuario desconectado');
        _load();
      } on MikroTikException catch (e) {
        _snack(e.message, isError: true);
      }
    }
  }

  Future<void> _disconnectAll() async {
    if (_sessions.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: const Text('Desconectar todos',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('Desconectar ${_sessions.length} sesiones activas?',
            style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Desconectar todos',
                  style: TextStyle(color: AppTheme.error))),
        ],
      ),
    );
    if (confirm == true) {
      final api = context.read<RouterProvider>().api;
      if (api == null) return;
      String? err;
      for (final s in _sessions) {
        if (s.id == null) continue;
        try {
          await api.disconnectSession(s.id!);
        } on MikroTikException catch (e) {
          err ??= e.message;
        }
      }
      if (err != null) _snack(err, isError: true);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.success.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.wifi, color: AppTheme.success, size: 16),
                    const SizedBox(width: 6),
                    Text('${_sessions.length} activos',
                        style: const TextStyle(
                            color: AppTheme.success,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const Spacer(),
              if (_sessions.isNotEmpty)
                TextButton.icon(
                  onPressed: _disconnectAll,
                  icon:
                      const Icon(Icons.wifi_off, color: AppTheme.error, size: 16),
                  label: const Text('Cortar todos',
                      style: TextStyle(color: AppTheme.error, fontSize: 12)),
                ),
              IconButton(
                icon: const Icon(Icons.refresh,
                    color: AppTheme.textSecondary, size: 20),
                onPressed: _load,
              ),
            ],
          ),
        ),
        // List
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.primary))
              : _sessions.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wifi_off,
                              size: 48,
                              color: AppTheme.textSecondary.withOpacity(0.3)),
                          const SizedBox(height: 12),
                          const Text('Sin sesiones activas',
                              style: TextStyle(
                                  color: AppTheme.textSecondary)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      color: AppTheme.primary,
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _sessions.length,
                        itemBuilder: (_, i) => _SessionCard(
                          session: _sessions[i],
                          onDisconnect: () => _disconnect(_sessions[i]),
                        ),
                      ),
                    ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class _SessionCard extends StatelessWidget {
  final ActiveSession session;
  final VoidCallback onDisconnect;

  const _SessionCard({required this.session, required this.onDisconnect});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider, width: 0.5),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.success.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child:
                const Icon(Icons.person, color: AppTheme.success, size: 24),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(session.user,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 15)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _infoChip(Icons.access_time, session.uptime),
                    const SizedBox(width: 8),
                    _infoChip(Icons.language, session.address),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _infoChip(Icons.download, session.trafficIn),
                    const SizedBox(width: 8),
                    _infoChip(Icons.upload, session.trafficOut),
                  ],
                ),
                const SizedBox(height: 2),
                Text(session.macAddress,
                    style: TextStyle(
                        color: AppTheme.textSecondary.withOpacity(0.6),
                        fontSize: 10,
                        fontFamily: 'monospace')),
              ],
            ),
          ),
          // Disconnect button
          IconButton(
            onPressed: onDisconnect,
            icon: const Icon(Icons.power_settings_new,
                color: AppTheme.error, size: 22),
            tooltip: 'Desconectar',
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.error.withOpacity(0.1),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppTheme.textSecondary, size: 12),
        const SizedBox(width: 3),
        Text(text,
            style:
                const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
      ],
    );
  }
}
