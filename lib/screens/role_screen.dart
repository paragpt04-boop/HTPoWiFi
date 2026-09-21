import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/router_provider.dart';
import '../utils/app_theme.dart';
import 'home_screen.dart';

class RoleScreen extends StatefulWidget {
  const RoleScreen({super.key});

  @override
  State<RoleScreen> createState() => _RoleScreenState();
}

class _RoleScreenState extends State<RoleScreen> {
  final _pinCtl = TextEditingController();
  bool _obscure = true;
  String? _error;
  AppRole? _selecting;

  @override
  void initState() {
    super.initState();
    // Si no hay PIN de admin, entrar como admin directo
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (!auth.hasAdminPin && !auth.hasVendorPin) {
        auth.setRole(AppRole.admin);
        _goHome();
      }
    });
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  void _tryLogin(AppRole role) {
    final auth = context.read<AuthProvider>();

    // Admin sin PIN configurado
    if (role == AppRole.admin && !auth.hasAdminPin) {
      auth.setRole(AppRole.admin);
      _goHome();
      return;
    }

    // Vendor sin PIN configurado
    if (role == AppRole.vendor && !auth.hasVendorPin) {
      setState(() => _error = 'No hay vendedores configurados.\nPide al admin que configure el PIN de vendedor.');
      return;
    }

    setState(() {
      _selecting = role;
      _error = null;
      _pinCtl.clear();
    });
  }

  void _confirmPin() {
    if (_selecting == null) return;
    final auth = context.read<AuthProvider>();
    final ok = auth.loginAs(_selecting!, _pinCtl.text.trim());
    if (ok) {
      _goHome();
    } else {
      setState(() => _error = 'PIN incorrecto');
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = context.watch<RouterProvider>();
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.wifi_tethering,
                      size: 40, color: AppTheme.primary),
                ),
                const SizedBox(height: 12),
                const Text('HTPoWiFi',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                        letterSpacing: 1.4)),
                const SizedBox(height: 4),
                // Router info
                Text(router.config?.host ?? '',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 13)),
                const SizedBox(height: 32),

                if (_selecting == null) ...[
                  // Role picker
                  const Text('Selecciona tu rol',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 14)),
                  const SizedBox(height: 20),

                  // Admin
                  _RoleButton(
                    icon: Icons.admin_panel_settings_rounded,
                    label: 'Administrador',
                    subtitle: 'Acceso completo al sistema',
                    color: AppTheme.primary,
                    onTap: () => _tryLogin(AppRole.admin),
                  ),
                  const SizedBox(height: 12),

                  // Vendor
                  _RoleButton(
                    icon: Icons.sell_rounded,
                    label: 'Vendedor',
                    subtitle: 'Solo crear tarjetas de acceso',
                    color: AppTheme.accent,
                    onTap: () => _tryLogin(AppRole.vendor),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: AppTheme.error.withOpacity(0.3)),
                      ),
                      child: Text(_error!,
                          style: const TextStyle(
                              color: AppTheme.error, fontSize: 13)),
                    ),
                  ],

                  // Config vendor PIN (solo si no hay ningún PIN de vendor)
                  if (!auth.hasVendorPin) ...[
                    const SizedBox(height: 24),
                    TextButton.icon(
                      onPressed: _showPinSetupDialog,
                      icon: const Icon(Icons.settings, size: 16),
                      label: const Text('Configurar PINs',
                          style: TextStyle(fontSize: 13)),
                    ),
                  ],
                ] else ...[
                  // PIN input
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.card,
                      borderRadius: BorderRadius.circular(16),
                      border:
                          Border.all(color: AppTheme.divider, width: 0.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _selecting == AppRole.admin
                                  ? Icons.admin_panel_settings_rounded
                                  : Icons.sell_rounded,
                              color: _selecting == AppRole.admin
                                  ? AppTheme.primary
                                  : AppTheme.accent,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _selecting == AppRole.admin
                                  ? 'PIN de Administrador'
                                  : 'PIN de Vendedor',
                              style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _pinCtl,
                          obscureText: _obscure,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          style: const TextStyle(
                              color: AppTheme.textPrimary, fontSize: 20,
                              letterSpacing: 8),
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            hintText: '••••',
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: AppTheme.textSecondary,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                          onSubmitted: (_) => _confirmPin(),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Text(_error!,
                              style: const TextStyle(
                                  color: AppTheme.error, fontSize: 13)),
                        ],
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => setState(() {
                                  _selecting = null;
                                  _error = null;
                                  _pinCtl.clear();
                                }),
                                child: const Text('Cancelar'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _confirmPin,
                                child: const Text('Entrar'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showPinSetupDialog() {
    final auth = context.read<AuthProvider>();
    final vendorCtl = TextEditingController();
    final adminCtl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: const Text('Configurar PINs',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Deja en blanco para no usar PIN.',
                style:
                    TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 16),
            TextField(
              controller: adminCtl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'PIN Admin (opcional)',
                prefixIcon: Icon(Icons.admin_panel_settings_rounded,
                    color: AppTheme.textSecondary),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: vendorCtl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'PIN Vendedor',
                prefixIcon: Icon(Icons.sell_rounded,
                    color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              if (adminCtl.text.isNotEmpty) {
                await auth.saveAdminPin(adminCtl.text.trim());
              }
              if (vendorCtl.text.isNotEmpty) {
                await auth.saveVendorPin(vendorCtl.text.trim());
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pinCtl.dispose();
    super.dispose();
  }
}

class _RoleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _RoleButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            color: color,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: color.withOpacity(0.5)),
            ],
          ),
        ),
      ),
    );
  }
}
