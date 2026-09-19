import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/router_config.dart';
import '../providers/router_provider.dart';
import '../utils/app_theme.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _hostCtl = TextEditingController();
  final _portCtl = TextEditingController(text: '80');
  final _userCtl = TextEditingController(text: 'admin');
  final _passCtl = TextEditingController();
  bool _obscure = true;
  bool _useSsl = false;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final prov = context.read<RouterProvider>();
    await prov.loadSavedConfig();
    if (prov.config != null) {
      _hostCtl.text = prov.config!.host;
      _portCtl.text = prov.config!.port.toString();
      _userCtl.text = prov.config!.username;
      _passCtl.text = prov.config!.password;
      _useSsl = prov.config!.useSsl;
      setState(() {});
    }
  }

  Future<void> _connect() async {
    if (_hostCtl.text.trim().isEmpty) return;
    final config = RouterConfig(
      host: _hostCtl.text.trim(),
      port: int.tryParse(_portCtl.text.trim()) ?? 80,
      username: _userCtl.text.trim(),
      password: _passCtl.text,
      useSsl: _useSsl,
    );
    final prov = context.read<RouterProvider>();
    final ok = await prov.connect(config);
    if (ok && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<RouterProvider>();
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
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.wifi_tethering,
                      size: 44, color: AppTheme.primary),
                ),
                const SizedBox(height: 16),
                const Text(
                  'HTPoWiFi',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Hotspot Manager',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 32),

                // Form card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.divider, width: 0.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Conectar al Router',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary)),
                      const SizedBox(height: 16),
                      // IP
                      TextField(
                        controller: _hostCtl,
                        style: const TextStyle(color: AppTheme.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'IP del Router',
                          hintText: '192.168.50.1',
                          prefixIcon:
                              Icon(Icons.router, color: AppTheme.textSecondary),
                        ),
                        keyboardType: TextInputType.url,
                      ),
                      const SizedBox(height: 12),
                      // Puerto
                      TextField(
                        controller: _portCtl,
                        style: const TextStyle(color: AppTheme.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Puerto',
                          hintText: '80',
                          prefixIcon: Icon(Icons.numbers,
                              color: AppTheme.textSecondary),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      // Usuario
                      TextField(
                        controller: _userCtl,
                        style: const TextStyle(color: AppTheme.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Usuario',
                          hintText: 'admin',
                          prefixIcon: Icon(Icons.person,
                              color: AppTheme.textSecondary),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Password
                      TextField(
                        controller: _passCtl,
                        style: const TextStyle(color: AppTheme.textPrimary),
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: 'Contraseña',
                          prefixIcon: const Icon(Icons.lock,
                              color: AppTheme.textSecondary),
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
                      ),
                      const SizedBox(height: 12),
                      // SSL toggle
                      Row(
                        children: [
                          Switch(
                            value: _useSsl,
                            activeColor: AppTheme.primary,
                            onChanged: (v) {
                              setState(() {
                                _useSsl = v;
                                _portCtl.text = v ? '443' : '80';
                              });
                            },
                          ),
                          const Text('Usar HTTPS',
                              style:
                                  TextStyle(color: AppTheme.textSecondary)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Error
                      if (prov.error != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: AppTheme.error.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppTheme.error.withOpacity(0.3)),
                          ),
                          child: Text(prov.error!,
                              style: const TextStyle(
                                  color: AppTheme.error, fontSize: 13)),
                        ),
                      // Botón
                      ElevatedButton(
                        onPressed: prov.isLoading ? null : _connect,
                        child: prov.isLoading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.black))
                            : const Text('Conectar'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'RouterOS v7 REST API',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _hostCtl.dispose();
    _portCtl.dispose();
    _userCtl.dispose();
    _passCtl.dispose();
    super.dispose();
  }
}
