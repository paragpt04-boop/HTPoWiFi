import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/router_provider.dart';
import '../services/mikrotik_api.dart';
import '../utils/app_theme.dart';
import 'role_screen.dart';

enum _WizardStep { scanning, ready, pickInterface, configNet, executing, done, error }

class SetupWizardScreen extends StatefulWidget {
  const SetupWizardScreen({super.key});

  @override
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends State<SetupWizardScreen> {
  _WizardStep _step = _WizardStep.scanning;
  Map<String, dynamic> _sysInfo = {};
  List<String> _interfaces = [];
  String _selectedInterface = '';
  String _gateway = '10.10.10.1';
  String _network = '10.10.10.0/24';
  String _poolRange = '10.10.10.2-10.10.10.254';
  String _serverName = 'hotspot1';
  String _errorMsg = '';
  List<String> _log = [];

  final _gatewayCtl = TextEditingController(text: '10.10.10.1');
  final _networkCtl = TextEditingController(text: '10.10.10.0/24');
  final _poolCtl = TextEditingController(text: '10.10.10.2-10.10.10.254');
  final _nameCtl = TextEditingController(text: 'hotspot1');

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    final api = context.read<RouterProvider>().api;
    if (api == null) return;

    setState(() => _step = _WizardStep.scanning);

    try {
      final info = await api.getSystemInfo();
      final configured = await api.isHotspotConfigured();

      if (!mounted) return;

      if (configured) {
        // Hotspot ya existe, recargar meta y pasar a roles
        await context.read<RouterProvider>().refreshMeta();
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const RoleScreen()),
        );
        return;
      }

      // Cargar interfaces
      final ifaces = await api.getInterfaces();
      final names = ifaces
          .where((i) {
            final t = (i['type'] ?? '').toString();
            return t == 'bridge' || t == 'ether' || t == 'vlan';
          })
          .map((i) => (i['name'] ?? '').toString())
          .where((n) => n.isNotEmpty)
          .toList();

      setState(() {
        _sysInfo = info;
        _interfaces = names;
        _selectedInterface = names.isNotEmpty ? names.first : '';
        _step = _WizardStep.ready;
      });
    } on MikroTikException catch (e) {
      setState(() {
        _errorMsg = e.message;
        _step = _WizardStep.error;
      });
    }
  }

  Future<void> _execute() async {
    setState(() {
      _step = _WizardStep.executing;
      _log = [];
    });

    final api = context.read<RouterProvider>().api;
    if (api == null) return;

    void addLog(String msg) {
      if (mounted) setState(() => _log.add(msg));
    }

    try {
      addLog('Configurando IP en $_selectedInterface...');
      await api.setupHotspot(
        interface: _selectedInterface,
        gatewayIp: _gateway,
        networkCidr: _network,
        poolRange: _poolRange,
        serverName: _serverName,
        onProgress: addLog,
      );

      addLog('✅ Hotspot configurado correctamente.');
      await context.read<RouterProvider>().refreshMeta();

      if (!mounted) return;
      setState(() => _step = _WizardStep.done);
    } on MikroTikException catch (e) {
      addLog('❌ ${e.message}');
      if (mounted) setState(() => _step = _WizardStep.error);
    }
  }

  void _goRoles() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const RoleScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Configurar Hotspot'),
        leading: _step == _WizardStep.executing
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_step) {
      case _WizardStep.scanning:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppTheme.primary),
              SizedBox(height: 16),
              Text('Analizando el router...',
                  style: TextStyle(color: AppTheme.textSecondary)),
            ],
          ),
        );

      case _WizardStep.ready:
        return _buildReadyStep();

      case _WizardStep.pickInterface:
        return _buildInterfaceStep();

      case _WizardStep.configNet:
        return _buildNetworkStep();

      case _WizardStep.executing:
        return _buildExecutingStep();

      case _WizardStep.done:
        return _buildDoneStep();

      case _WizardStep.error:
        return _buildErrorStep();
    }
  }

  Widget _buildReadyStep() {
    return ListView(
      children: [
        // Info del router
        _InfoCard(
          icon: Icons.router,
          title: _sysInfo['identity']?.toString() ?? 'MikroTik',
          children: [
            _infoRow('Modelo', _sysInfo['board']?.toString() ?? '-'),
            _infoRow('RouterOS', 'v${_sysInfo['version'] ?? '-'}'),
            _infoRow('CPU', '${_sysInfo['cpu-load'] ?? '-'}%'),
          ],
        ),
        const SizedBox(height: 16),

        // Advertencia
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.warning.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.warning.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: AppTheme.warning, size: 22),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'No se detectó Hotspot configurado en este router.\n'
                  'El asistente lo configurará automáticamente.',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        ElevatedButton.icon(
          onPressed: () => setState(() => _step = _WizardStep.pickInterface),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Iniciar configuración'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: _goRoles,
          child: const Text('Omitir (configurar manualmente)'),
        ),
      ],
    );
  }

  Widget _buildInterfaceStep() {
    return ListView(
      children: [
        const _StepHeader(step: '1 / 3', title: 'Seleccionar interfaz'),
        const SizedBox(height: 8),
        const Text(
            'Elige la interfaz donde los clientes se conectarán al hotspot '
            '(generalmente un bridge o ethernet).',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        const SizedBox(height: 20),

        if (_interfaces.isEmpty)
          const Center(
              child: Text('No se encontraron interfaces disponibles.',
                  style: TextStyle(color: AppTheme.error)))
        else
          ..._interfaces.map((iface) => RadioListTile<String>(
                value: iface,
                groupValue: _selectedInterface,
                onChanged: (v) => setState(() => _selectedInterface = v!),
                activeColor: AppTheme.primary,
                title: Text(iface,
                    style: const TextStyle(color: AppTheme.textPrimary)),
                tileColor: AppTheme.card,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              )),

        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _selectedInterface.isEmpty
              ? null
              : () => setState(() => _step = _WizardStep.configNet),
          child: const Text('Siguiente'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => setState(() => _step = _WizardStep.ready),
          child: const Text('Atrás'),
        ),
      ],
    );
  }

  Widget _buildNetworkStep() {
    return ListView(
      children: [
        const _StepHeader(step: '2 / 3', title: 'Configurar red'),
        const SizedBox(height: 8),
        const Text(
            'Ajusta los parámetros de red para el hotspot. '
            'Los valores por defecto funcionan para la mayoría de los casos.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        const SizedBox(height: 20),
        TextField(
          controller: _gatewayCtl,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            labelText: 'IP del Gateway (router)',
            hintText: '10.10.10.1',
            prefixIcon:
                Icon(Icons.router, color: AppTheme.textSecondary),
          ),
          onChanged: (v) => _gateway = v.trim(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _networkCtl,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            labelText: 'Red (CIDR)',
            hintText: '10.10.10.0/24',
            prefixIcon:
                Icon(Icons.lan, color: AppTheme.textSecondary),
          ),
          onChanged: (v) => _network = v.trim(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _poolCtl,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            labelText: 'Rango de IPs para clientes',
            hintText: '10.10.10.2-10.10.10.254',
            prefixIcon:
                Icon(Icons.device_hub, color: AppTheme.textSecondary),
          ),
          onChanged: (v) => _poolRange = v.trim(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nameCtl,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            labelText: 'Nombre del servidor hotspot',
            hintText: 'hotspot1',
            prefixIcon:
                Icon(Icons.wifi_tethering, color: AppTheme.textSecondary),
          ),
          onChanged: (v) => _serverName = v.trim(),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: _execute,
          icon: const Icon(Icons.rocket_launch),
          label: const Text('Instalar Hotspot'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => setState(() => _step = _WizardStep.pickInterface),
          child: const Text('Atrás'),
        ),
      ],
    );
  }

  Widget _buildExecutingStep() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(color: AppTheme.primary),
        const SizedBox(height: 20),
        const Text('Configurando el router...',
            style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _log
                .map((l) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(l,
                          style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                              fontFamily: 'monospace')),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildDoneStep() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.success.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle,
                color: AppTheme.success, size: 48),
          ),
          const SizedBox(height: 20),
          const Text('¡Hotspot configurado!',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('El hotspot está listo para usarse.',
              style:
                  TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _goRoles,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Continuar'),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorStep() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: AppTheme.error, size: 56),
          const SizedBox(height: 16),
          const Text('Error',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.error.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(_errorMsg,
                style: const TextStyle(
                    color: AppTheme.error, fontSize: 13),
                textAlign: TextAlign.center),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _scan,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _goRoles,
            child: const Text('Omitir'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: [
        Text('$label: ',
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 13)),
        Text(value,
            style: const TextStyle(
                color: AppTheme.textPrimary, fontSize: 13)),
      ]),
    );
  }

  @override
  void dispose() {
    _gatewayCtl.dispose();
    _networkCtl.dispose();
    _poolCtl.dispose();
    _nameCtl.dispose();
    super.dispose();
  }
}

class _StepHeader extends StatelessWidget {
  final String step;
  final String title;
  const _StepHeader({required this.step, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.primary.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(step,
            style: const TextStyle(
                color: AppTheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ),
      const SizedBox(width: 10),
      Text(title,
          style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w600)),
    ]);
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const _InfoCard(
      {required this.icon, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: AppTheme.primary, size: 20),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}
