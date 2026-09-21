import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/router_provider.dart';
import '../utils/app_theme.dart';
import 'login_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final router = context.watch<RouterProvider>();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Configuración')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Router info
          _SectionHeader('Conexión activa'),
          _InfoTile(
            icon: Icons.router,
            label: 'Router',
            value: router.config?.host ?? '-',
          ),
          _InfoTile(
            icon: Icons.person,
            label: 'Usuario',
            value: router.config?.username ?? '-',
          ),
          _InfoTile(
            icon: Icons.swap_horiz,
            label: 'Protocolo',
            value: router.config?.useSsl == true ? 'HTTPS' : 'HTTP',
          ),
          const SizedBox(height: 24),

          // PINs
          _SectionHeader('Seguridad y roles'),
          _ActionTile(
            icon: Icons.admin_panel_settings_rounded,
            iconColor: AppTheme.primary,
            label: 'PIN de Administrador',
            subtitle: auth.hasAdminPin ? 'Configurado' : 'Sin PIN (acceso libre)',
            onTap: () => _showChangePinDialog(context, AppRole.admin),
          ),
          _ActionTile(
            icon: Icons.sell_rounded,
            iconColor: AppTheme.accent,
            label: 'PIN de Vendedor',
            subtitle: auth.hasVendorPin ? 'Configurado' : 'No configurado',
            onTap: () => _showChangePinDialog(context, AppRole.vendor),
          ),
          const SizedBox(height: 24),

          // Danger zone
          _SectionHeader('Sesión'),
          _ActionTile(
            icon: Icons.wifi_off,
            iconColor: AppTheme.error,
            label: 'Desconectar router',
            subtitle: 'Volver a la pantalla de conexión',
            onTap: () {
              router.disconnect();
              auth.logout();
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (_) => false,
              );
            },
          ),
        ],
      ),
    );
  }

  void _showChangePinDialog(BuildContext context, AppRole role) {
    final auth = context.read<AuthProvider>();
    final isAdmin = role == AppRole.admin;
    final currentCtl = TextEditingController();
    final newCtl = TextEditingController();
    final confirmCtl = TextEditingController();
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: AppTheme.card,
          title: Text(
            isAdmin ? 'PIN de Administrador' : 'PIN de Vendedor',
            style: const TextStyle(color: AppTheme.textPrimary),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if ((isAdmin && auth.hasAdminPin) ||
                  (!isAdmin && auth.hasVendorPin))
                TextField(
                  controller: currentCtl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  obscureText: true,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'PIN actual',
                    prefixIcon:
                        Icon(Icons.lock, color: AppTheme.textSecondary),
                  ),
                ),
              const SizedBox(height: 10),
              TextField(
                controller: newCtl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                obscureText: true,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Nuevo PIN (vacío = sin PIN)',
                  prefixIcon:
                      Icon(Icons.lock_open, color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: confirmCtl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                obscureText: true,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Confirmar nuevo PIN',
                  prefixIcon:
                      Icon(Icons.lock_outline, color: AppTheme.textSecondary),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!,
                    style: const TextStyle(
                        color: AppTheme.error, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                // Validar PIN actual
                final hasCurrent = isAdmin
                    ? auth.hasAdminPin
                    : auth.hasVendorPin;
                if (hasCurrent) {
                  final ok = auth.loginAs(role, currentCtl.text.trim());
                  // Restablecer rol original
                  auth.setRole(AppRole.admin);
                  if (!ok) {
                    setS(() => error = 'PIN actual incorrecto');
                    return;
                  }
                }
                if (newCtl.text != confirmCtl.text) {
                  setS(() => error = 'Los PINs no coinciden');
                  return;
                }
                if (isAdmin) {
                  if (newCtl.text.isEmpty) {
                    await auth.clearAdminPin();
                  } else {
                    await auth.saveAdminPin(newCtl.text.trim());
                  }
                } else {
                  if (newCtl.text.isEmpty) {
                    await auth.clearVendorPin();
                  } else {
                    await auth.saveVendorPin(newCtl.text.trim());
                  }
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(title.toUpperCase(),
          style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2)),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoTile(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider, width: 0.5),
      ),
      child: Row(children: [
        Icon(icon, color: AppTheme.textSecondary, size: 20),
        const SizedBox(width: 14),
        Expanded(
          child: Text(label,
              style: const TextStyle(color: AppTheme.textSecondary)),
        ),
        Text(value,
            style: const TextStyle(
                color: AppTheme.textPrimary, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider, width: 0.5),
      ),
      child: ListTile(
        leading: Icon(icon, color: iconColor, size: 22),
        title: Text(label,
            style: const TextStyle(
                color: AppTheme.textPrimary, fontSize: 14)),
        subtitle: Text(subtitle,
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right,
            color: AppTheme.textSecondary, size: 20),
        onTap: onTap,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
