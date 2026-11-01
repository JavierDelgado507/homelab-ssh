import 'package:flutter/material.dart';
import '../main.dart';
import '../models/host.dart';
import '../services/i18n.dart';
import '../services/storage_service.dart';
import 'terminal_screen.dart';

// Host especial para el shell local del dispositivo
final kLocalHost = Host(
  id: '__local__',
  name: 'Local terminal',
  hostname: 'local',
  port: 0,
  username: '',
  authType: 'local',
);

// Datos de una pestaña abierta
class TerminalTab {
  final Host host;
  final GlobalKey<TerminalScreenState> key;
  bool connected;
  String label;

  TerminalTab(this.host)
      : key = GlobalKey<TerminalScreenState>(),
        connected = false,
        label = host.name;
}

/// Almacén de sesiones compartido. Las pestañas viven aquí (no en la pantalla)
/// para que sobrevivan al volver al menú principal: la raíz mantiene montada
/// TerminalTabsScreen aunque no se vea.
class TabsHub extends ChangeNotifier {
  TabsHub._();
  static final instance = TabsHub._();

  final tabs = <TerminalTab>[];
  int active = 0;
  bool showing = false; // true → se ve la pantalla de terminales

  void open(Host host) {
    tabs.add(TerminalTab(host));
    active = tabs.length - 1;
    showing = true;
    notifyListeners();
  }

  void goHome() {
    showing = false;
    FocusManager.instance.primaryFocus?.unfocus();
    notifyListeners();
  }

  void show() {
    if (tabs.isEmpty) return;
    showing = true;
    notifyListeners();
  }

  void refresh() => notifyListeners();
}

class TerminalTabsScreen extends StatefulWidget {
  const TerminalTabsScreen({super.key});

  @override
  State<TerminalTabsScreen> createState() => _TerminalTabsScreenState();
}

class _TerminalTabsScreenState extends State<TerminalTabsScreen> {
  final _hub = TabsHub.instance;
  List<TerminalTab> get _tabs => _hub.tabs;
  int get _active => _hub.active;

  @override
  void initState() {
    super.initState();
    _hub.addListener(_onHub);
  }

  @override
  void dispose() {
    _hub.removeListener(_onHub);
    super.dispose();
  }

  void _onHub() {
    if (!mounted) return;
    setState(() {});
    if (_hub.showing && _tabs.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_hub.showing && _tabs.isNotEmpty) {
          _tabs[_active].key.currentState?.requestFocus();
        }
      });
    }
  }

  void _addTab(Host host) => _hub.open(host);

  void _closeTab(int idx) {
    // Desconectar SSH antes de destruir
    _tabs[idx].key.currentState?.disconnect();
    _tabs.removeAt(idx);
    if (_active >= _tabs.length) _hub.active = _tabs.isEmpty ? 0 : _tabs.length - 1;
    if (_tabs.isEmpty) {
      _hub.goHome();
    } else {
      _hub.refresh();
    }
  }

  void _switchTab(int idx) {
    _hub.active = idx;
    _hub.refresh();
  }

  // Abre un selector de hosts para añadir nueva pestaña
  Future<void> _pickHostForNewTab() async {
    final hosts = await StorageService.getHosts();
    if (!mounted || hosts.isEmpty) return;

    final host = await showModalBottomSheet<Host>(
      context: context,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _HostPicker(hosts: hosts),
    );
    if (host != null) _addTab(host);
  }

  // ── Barra de pestañas estilo Termius ──────────────────────────────────────
  Widget _buildTabBar() {
    return Container(
      height: 38,
      color: const Color(0xFF0E1320),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              itemCount: _tabs.length,
              itemBuilder: (_, i) => _buildTabPill(i),
            ),
          ),
          // Botón "+"
          GestureDetector(
            onTap: _pickHostForNewTab,
            child: Container(
              width: 36, height: 28,
              margin: const EdgeInsets.only(right: 6, top: 5, bottom: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF1E2740),
                borderRadius: BorderRadius.circular(7),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.add, size: 18, color: kTextSec),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabPill(int i) {
    final tab    = _tabs[i];
    final active = i == _active;
    final dotColor = tab.connected
        ? kSuccess
        : (tab.label == tr('Connecting…') ? const Color(0xFFFFD93D) : kError);

    return GestureDetector(
      onTap: () => _switchTab(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        constraints: const BoxConstraints(minWidth: 80, maxWidth: 160),
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: active
              ? kAccent.withOpacity(0.18)
              : const Color(0xFF1A2035),
          borderRadius: BorderRadius.circular(7),
          border: active
              ? Border.all(color: kAccent.withOpacity(0.6), width: 1)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Punto de estado
            Container(
              width: 6, height: 6,
              margin: const EdgeInsets.only(right: 5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor,
              ),
            ),
            // Nombre del host
            Flexible(
              child: Text(
                tab.host.name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  color: active ? kAccent : kTextSec,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            // Cerrar pestaña
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _closeTab(i),
              child: Padding(
                padding: const EdgeInsets.only(left: 5),
                child: Icon(
                  Icons.close,
                  size: 13,
                  color: active ? kAccent.withOpacity(0.8) : kTextSec.withOpacity(0.6),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── AppBar ─────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    final tab = _tabs.isEmpty ? null : _tabs[_active];
    return AppBar(
      backgroundColor: kSurface,
      titleSpacing: 0,
      leading: IconButton(
        icon: const Icon(Icons.home_outlined, size: 20),
        tooltip: tr('Home (sessions stay alive)'),
        onPressed: _hub.goHome,
      ),
      title: tab == null
          ? const SizedBox()
          : Row(
              children: [
                Container(
                  width: 8, height: 8,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tab.connected ? kSuccess : kError,
                  ),
                ),
                Expanded(
                  child: Text(
                    tab.label,
                    style: const TextStyle(fontSize: 14, color: kTextPri),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
      actions: [
        if (tab != null && !tab.connected)
          IconButton(
            icon: const Icon(Icons.refresh, size: 20, color: kTextSec),
            onPressed: () => tab.key.currentState?.reconnect(),
          ),
        IconButton(
          icon: const Icon(Icons.text_decrease, size: 18, color: kTextSec),
          onPressed: () => tab?.key.currentState?.zoomOut(),
        ),
        IconButton(
          icon: const Icon(Icons.text_increase, size: 18, color: kTextSec),
          onPressed: () => tab?.key.currentState?.zoomIn(),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_tabs.isEmpty) return const SizedBox();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      resizeToAvoidBottomInset: true,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildTabBar(),
          Expanded(
            // IndexedStack mantiene el estado de todos los terminales en memoria
            child: IndexedStack(
              index: _active,
              children: _tabs.asMap().entries.map((e) {
                final i   = e.key;
                final tab = e.value;
                return TerminalScreen(
                  key: tab.key,
                  host: tab.host,
                  showAppBar: false,
                  active: _hub.showing && i == _active,
                  onStatusChanged: (connected, label) {
                    if (!mounted) return;
                    setState(() {
                      tab.connected = connected;
                      tab.label     = label;
                      // Actualizar el AppBar si esta es la pestaña activa
                      if (i == _active) {
                        // setState ya disparado — se repinta
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Selector de host para nueva pestaña ───────────────────────────────────────
class _HostPicker extends StatelessWidget {
  final List<Host> hosts;
  const _HostPicker({required this.hosts});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        Container(
          width: 36, height: 4,
          decoration: BoxDecoration(
            color: kTextSec.withOpacity(0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 12),
        Text(tr('New terminal'),
          style: TextStyle(
              color: kTextPri, fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.5,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
            children: [
              // Opción local siempre al principio
              _hostTile(context, kLocalHost,
                  icon: Icons.phone_android_outlined,
                  iconColor: const Color(0xFFFFD93D),
                  subtitle: 'A shell on this device'),
              if (hosts.isNotEmpty)
                const Divider(height: 16, color: Color(0xFF252D4A)),
              ...hosts.map((h) => _hostTile(context, h,
                  icon: Icons.computer_outlined,
                  iconColor: kAccent,
                  subtitle: '${h.username}@${h.hostname}:${h.port}')),
            ],
          ),
        ),
      ],
    );
  }

  Widget _hostTile(BuildContext context, Host h, {
    required IconData icon,
    required Color iconColor,
    required String subtitle,
  }) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      leading: Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(h.name,
          style: const TextStyle(color: kTextPri, fontSize: 14)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: kTextSec, fontSize: 12)),
      onTap: () => Navigator.pop(context, h),
    );
  }
}
