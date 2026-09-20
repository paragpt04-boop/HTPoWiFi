import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/hotspot_user.dart';
import '../providers/router_provider.dart';
import '../services/mikrotik_api.dart';
import '../utils/app_theme.dart';

class UsersTab extends StatefulWidget {
  const UsersTab({super.key});

  @override
  State<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<UsersTab> {
  List<HotspotUser> _users = [];
  List<HotspotUser> _filtered = [];
  bool _loading = true;
  final _searchCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final api = context.read<RouterProvider>().api;
    if (api == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final users = await api.getUsers();
      if (!mounted) return;
      setState(() {
        _users = users;
        _filtered = _applyFilter(users, _searchCtl.text);
        _loading = false;
      });
    } on MikroTikException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnack(e.message, isError: true);
    }
  }

  List<HotspotUser> _applyFilter(List<HotspotUser> src, String query) {
    if (query.trim().isEmpty) return src;
    final q = query.toLowerCase();
    return src.where((u) => u.name.toLowerCase().contains(q)).toList();
  }

  void _filter(String query) {
    setState(() => _filtered = _applyFilter(_users, query));
  }

  Future<void> _deleteUser(HotspotUser user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: const Text('Eliminar usuario',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('Eliminar "${user.name}"?',
            style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  const Text('Eliminar', style: TextStyle(color: AppTheme.error))),
        ],
      ),
    );
    if (confirm == true && user.id != null) {
      final api = context.read<RouterProvider>().api;
      if (api == null) return;
      try {
        await api.deleteUser(user.id!);
        _showSnack('Usuario eliminado');
        _load();
      } on MikroTikException catch (e) {
        _showSnack(e.message, isError: true);
      }
    }
  }

  Future<void> _resetUptime(HotspotUser user) async {
    if (user.id == null) return;
    final api = context.read<RouterProvider>().api;
    if (api == null) return;
    try {
      await api.resetUserUptime(user.id!);
      _showSnack('Tiempo reiniciado');
      _load();
    } on MikroTikException catch (e) {
      _showSnack(e.message, isError: true);
    }
  }

  Future<void> _toggleUser(HotspotUser user) async {
    if (user.id == null) return;
    final api = context.read<RouterProvider>().api;
    if (api == null) return;
    try {
      await api.toggleUser(user.id!, !user.disabled);
      _showSnack(user.disabled ? 'Usuario habilitado' : 'Usuario deshabilitado');
      _load();
    } on MikroTikException catch (e) {
      _showSnack(e.message, isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppTheme.error : AppTheme.success,
      duration: Duration(seconds: isError ? 6 : 2),
    ));
  }

  void _showAddDialog() {
    final prov = context.read<RouterProvider>();
    final nameCtl = TextEditingController();
    final passCtl = TextEditingController();
    String selectedTime = '1h';
    String selectedServer = prov.selectedServer;
    String selectedProfile = prov.selectedProfile;
    final times = ['5m', '30m', '1h', '2h', '5h', '12h', '1d', '3d', '7d', '30d'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: AppTheme.card,
          title: const Text('Nuevo Usuario',
              style: TextStyle(color: AppTheme.textPrimary)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtl,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Usuario',
                    prefixIcon:
                        Icon(Icons.person, color: AppTheme.textSecondary),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passCtl,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon:
                        Icon(Icons.lock, color: AppTheme.textSecondary),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedTime,
                  dropdownColor: AppTheme.cardLight,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Tiempo límite',
                    prefixIcon:
                        Icon(Icons.timer, color: AppTheme.textSecondary),
                  ),
                  items: times
                      .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(_timeLabel(t))))
                      .toList(),
                  onChanged: (v) => setDlgState(() => selectedTime = v!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: prov.servers.contains(selectedServer)
                      ? selectedServer
                      : prov.servers.first,
                  dropdownColor: AppTheme.cardLight,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Servidor hotspot',
                    prefixIcon:
                        Icon(Icons.dns, color: AppTheme.textSecondary),
                  ),
                  items: prov.servers
                      .map((sv) =>
                          DropdownMenuItem(value: sv, child: Text(sv)))
                      .toList(),
                  onChanged: (v) => setDlgState(() => selectedServer = v!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: prov.profiles.contains(selectedProfile)
                      ? selectedProfile
                      : prov.profiles.first,
                  dropdownColor: AppTheme.cardLight,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Perfil',
                    prefixIcon: Icon(Icons.speed,
                        color: AppTheme.textSecondary),
                  ),
                  items: prov.profiles
                      .map((pf) =>
                          DropdownMenuItem(value: pf, child: Text(pf)))
                      .toList(),
                  onChanged: (v) => setDlgState(() => selectedProfile = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                if (nameCtl.text.trim().isEmpty ||
                    passCtl.text.trim().isEmpty) {
                  return;
                }
                Navigator.pop(ctx);
                final api = context.read<RouterProvider>().api;
                if (api == null) {
                  _showSnack('Sin conexion al router', isError: true);
                  return;
                }
                final user = HotspotUser(
                  name: nameCtl.text.trim(),
                  password: passCtl.text.trim(),
                  server: selectedServer,
                  profile: selectedProfile,
                  limitUptime: selectedTime,
                );
                try {
                  await api.addUser(user);
                  _showSnack('Usuario creado');
                  _load();
                } on MikroTikException catch (e) {
                  _showSnack(e.message, isError: true);
                }
              },
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );
  }

  String _timeLabel(String code) {
    final map = {
      '5m': '5 minutos',
      '30m': '30 minutos',
      '1h': '1 hora',
      '2h': '2 horas',
      '5h': '5 horas',
      '12h': '12 horas',
      '1d': '1 día',
      '3d': '3 días',
      '7d': '7 días',
      '30d': '30 días',
    };
    return map[code] ?? code;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.person_add),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: 'Buscar usuario...',
                prefixIcon:
                    const Icon(Icons.search, color: AppTheme.textSecondary),
                suffixIcon: _searchCtl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear,
                            color: AppTheme.textSecondary),
                        onPressed: () {
                          _searchCtl.clear();
                          _filter('');
                        })
                    : null,
              ),
              onChanged: _filter,
            ),
          ),
          // Count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('${_filtered.length} usuarios',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 13)),
                const Spacer(),
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
                    child:
                        CircularProgressIndicator(color: AppTheme.primary))
                : RefreshIndicator(
                    color: AppTheme.primary,
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) => _UserCard(
                        user: _filtered[i],
                        onDelete: () => _deleteUser(_filtered[i]),
                        onReset: () => _resetUptime(_filtered[i]),
                        onToggle: () => _toggleUser(_filtered[i]),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }
}

class _UserCard extends StatelessWidget {
  final HotspotUser user;
  final VoidCallback onDelete;
  final VoidCallback onReset;
  final VoidCallback onToggle;

  const _UserCard({
    required this.user,
    required this.onDelete,
    required this.onReset,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isExpired = user.isExpired;
    final statusColor =
        user.disabled ? AppTheme.error : (isExpired ? AppTheme.warning : AppTheme.success);
    final statusText =
        user.disabled ? 'Deshabilitado' : (isExpired ? 'Expirado' : 'Activo');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Avatar
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.person, color: statusColor, size: 22),
              ),
              const SizedBox(width: 12),
              // Name & status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.name,
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 15)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(statusText,
                            style:
                                TextStyle(color: statusColor, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
              // Actions
              PopupMenuButton<String>(
                color: AppTheme.cardLight,
                icon: const Icon(Icons.more_vert,
                    color: AppTheme.textSecondary, size: 20),
                onSelected: (v) {
                  switch (v) {
                    case 'reset':
                      onReset();
                      break;
                    case 'toggle':
                      onToggle();
                      break;
                    case 'delete':
                      onDelete();
                      break;
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                      value: 'reset',
                      child: Row(children: [
                        Icon(Icons.restore, color: AppTheme.primary, size: 18),
                        SizedBox(width: 8),
                        Text('Reiniciar tiempo',
                            style: TextStyle(color: AppTheme.textPrimary))
                      ])),
                  PopupMenuItem(
                      value: 'toggle',
                      child: Row(children: [
                        Icon(
                            user.disabled
                                ? Icons.play_arrow
                                : Icons.pause,
                            color: AppTheme.warning,
                            size: 18),
                        const SizedBox(width: 8),
                        Text(
                            user.disabled ? 'Habilitar' : 'Deshabilitar',
                            style: const TextStyle(
                                color: AppTheme.textPrimary))
                      ])),
                  const PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        Icon(Icons.delete, color: AppTheme.error, size: 18),
                        SizedBox(width: 8),
                        Text('Eliminar',
                            style: TextStyle(color: AppTheme.error))
                      ])),
                ],
              ),
            ],
          ),
          if (user.limitUptime != null) ...[
            const SizedBox(height: 10),
            // Progress bar
            Row(
              children: [
                const Icon(Icons.timer, color: AppTheme.textSecondary, size: 14),
                const SizedBox(width: 6),
                Text('Restante: ${user.remainingTime}',
                    style:
                        const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                const Spacer(),
                Text('Límite: ${user.limitUptime}',
                    style:
                        const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: user.usagePercent,
                minHeight: 5,
                backgroundColor: AppTheme.divider,
                valueColor: AlwaysStoppedAnimation(
                    user.usagePercent > 0.8 ? AppTheme.error : AppTheme.primary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
