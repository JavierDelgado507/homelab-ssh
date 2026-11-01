import 'package:flutter/material.dart';
import 'package:quick_actions/quick_actions.dart';

import '../main.dart';
import '../models/host.dart';
import '../services/i18n.dart';
import '../services/storage_service.dart';
import '../services/ssh_keepalive_service.dart';
import 'add_host_screen.dart';
import 'discover_screen.dart';
import 'sftp_screen.dart';
import 'terminal_tabs_screen.dart' show TabsHub, kLocalHost;

// Colores de icono por host (rota por índice)
const _iconColors = [
  Color(0xFF4ECDC4), Color(0xFF5B8AF5), Color(0xFFFF6B6B),
  Color(0xFFFFD93D), Color(0xFF6BCB77), Color(0xFFFF8E53),
  Color(0xFFC77DFF), Color(0xFF4FC3F7),
];

class HostsScreen extends StatefulWidget {
  const HostsScreen({super.key});

  @override
  State<HostsScreen> createState() => _HostsScreenState();
}

class _HostsScreenState extends State<HostsScreen> {
  List<Host> _hosts = [];
  final _searchCtrl = TextEditingController();
  String _query = '';
  String _groupFilter = ''; // '' = todos
  final _quickActions = const QuickActions();

  @override
  void initState() {
    super.initState();
    _load();
    kDataChanged.addListener(_load);
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text));
    SshKeepaliveService.requestPermissions();
    // Accesos directos al mantener pulsado el icono de la app
    _quickActions.initialize((type) async {
      if (!type.startsWith('host:')) return;
      final hosts = await StorageService.getHosts();
      final idx = hosts.indexWhere((h) => h.id == type.substring(5));
      if (idx >= 0) TabsHub.instance.open(hosts[idx]);
    });
  }

  @override
  void dispose() {
    kDataChanged.removeListener(_load);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final hosts = await StorageService.getHosts();
    if (mounted) setState(() => _hosts = hosts);
    _quickActions.setShortcutItems(hosts
        .take(4)
        .map((h) => ShortcutItem(type: 'host:${h.id}', localizedTitle: h.name))
        .toList());
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    setState(() => _hosts.insert(newIndex, _hosts.removeAt(oldIndex)));
    await StorageService.saveHosts(_hosts);
    _load();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openAddHost([Host? host]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddHostScreen(host: host)),
    );
    if (saved == true) _load();
  }

  Future<void> _deleteHost(Host host) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(tr('Delete host'), style: TextStyle(color: kTextPri)),
        content: Text(
          Tr.es ? '¿Eliminar "${host.name}"?' : 'Delete "${host.name}"?',
          style: const TextStyle(color: kTextSec),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Cancel'), style: TextStyle(color: kTextSec)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Delete'), style: TextStyle(color: kError)),
          ),
        ],
      ),
    );
    if (ok == true) {
      _hosts.removeWhere((h) => h.id == host.id);
      await StorageService.saveHosts(_hosts);
      await StorageService.deletePassword(host.id);
      _load();
    }
  }

  List<String> get _groups {
    final gs = _hosts
        .map((h) => h.group)
        .where((g) => g.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return gs;
  }

  // Entiende "usuario@host:puerto", "ssh usuario@host -p puerto" o una IP
  static ({String user, String host, int port})? _parseTarget(String input) {
    var s = input.trim();
    final hadSshPrefix = s.toLowerCase().startsWith('ssh ');
    if (hadSshPrefix) s = s.substring(4).trim();
    int? pFlag;
    final mp = RegExp(r'\s+-p\s*(\d{1,5})\s*$').firstMatch(s);
    if (mp != null) {
      pFlag = int.tryParse(mp.group(1)!);
      s = s.substring(0, mp.start).trim();
    }
    final m =
        RegExp(r'^(?:([\w.\-]+)@)?([\w.\-]+)(?::(\d{1,5}))?$').firstMatch(s);
    if (m == null) return null;
    final host = m.group(2)!;
    // Una palabra suelta es búsqueda normal, salvo que venga de "ssh …" o -p
    if (!hadSshPrefix &&
        pFlag == null &&
        m.group(1) == null &&
        m.group(3) == null &&
        !host.contains('.')) {
      return null;
    }
    return (
      user: m.group(1) ?? 'root',
      host: host,
      port: pFlag ?? int.tryParse(m.group(3) ?? '') ?? 22,
    );
  }

  ({String user, String host, int port})? get _quickTarget =>
      _parseTarget(_query);

  // Diálogo de conexión rápida: dirección editable + contraseña; abre
  // terminal o SFTP según [sftp].
  Future<void> _connectDialog({String initialAddress = '',
      bool sftp = false}) async {
    final addrCtrl = TextEditingController(text: initialAddress);
    final pwCtrl = TextEditingController();
    var save = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: kCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text(tr(sftp ? 'Connect via SFTP' : 'Quick connect'),
              style: const TextStyle(color: kTextPri, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: addrCtrl,
                autofocus: initialAddress.isEmpty,
                keyboardType: TextInputType.url,
                style: const TextStyle(
                    color: kTextPri, fontFamily: 'JetBrainsMono', fontSize: 14),
                decoration: InputDecoration(
                  labelText: tr('Address'),
                  hintText: tr('root@192.168.1.99:22'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pwCtrl,
                obscureText: true,
                autofocus: initialAddress.isNotEmpty,
                style: const TextStyle(color: kTextPri),
                decoration: InputDecoration(labelText: tr('Password')),
                onSubmitted: (_) => Navigator.pop(ctx, true),
              ),
              CheckboxListTile(
                value: save,
                contentPadding: EdgeInsets.zero,
                activeColor: kAccent,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(tr('Save to hosts'),
                    style: TextStyle(color: kTextSec, fontSize: 14)),
                onChanged: (v) => setD(() => save = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:
                  Text(tr('Cancel'), style: TextStyle(color: kTextSec)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Connect'),
                  style:
                      TextStyle(color: kAccent, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final t = _parseTarget(addrCtrl.text);
    if (t == null) {
      _snack('Invalid address');
      return;
    }
    final host = Host(
      name: '${t.user}@${t.host}',
      hostname: t.host,
      port: t.port,
      username: t.user,
    );
    if (pwCtrl.text.isNotEmpty) {
      await StorageService.savePassword(host.id, pwCtrl.text);
    }
    if (save) {
      _hosts.add(host);
      await StorageService.saveHosts(_hosts);
      await _load();
    }
    _searchCtrl.clear();
    if (sftp) {
      if (!mounted) return;
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => SftpScreen(host: host)));
    } else {
      TabsHub.instance.open(host);
    }
  }

  // Hoja «Formas de conectar» (estilo Termius)
  void _showWaysToConnect() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Text(tr('Ways to connect'),
                style: TextStyle(
                    color: kTextPri,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            _wayTile(ctx, Icons.phone_android_outlined,
                const Color(0xFFFFD93D), tr('Local terminal'),
                tr('A shell on this device'), () {
              Navigator.pop(ctx);
              TabsHub.instance.open(kLocalHost);
            }),
            _wayTile(ctx, Icons.dns_outlined, kAccent, tr('Add host'),
                tr('Save a new server'), () {
              Navigator.pop(ctx);
              _openAddHost();
            }),
            _wayTile(ctx, Icons.folder_open_outlined, kAccent2,
                tr('Connect via SFTP'), tr('Browse files without opening a terminal'),
                () {
              Navigator.pop(ctx);
              _connectDialog(sftp: true);
            }),
            _wayTile(ctx, Icons.wifi_find_outlined, const Color(0xFF6BCB77),
                tr('Discover local devices'), tr('Scan your LAN for SSH servers'),
                () async {
              Navigator.pop(ctx);
              final ip = await Navigator.push<String>(context,
                  MaterialPageRoute(builder: (_) => const DiscoverScreen()));
              if (ip != null && mounted) {
                _connectDialog(initialAddress: 'root@$ip');
              }
            }),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _wayTile(BuildContext ctx, IconData icon, Color color, String title,
      String subtitle, VoidCallback onTap) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title,
          style: const TextStyle(color: kTextPri, fontSize: 15)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: kTextSec, fontSize: 12)),
      onTap: onTap,
    );
  }

  List<Host> get _filtered {
    Iterable<Host> out = _hosts;
    if (_groupFilter.isNotEmpty) {
      out = out.where((h) => h.group == _groupFilter);
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      out = out.where((h) =>
          h.name.toLowerCase().contains(q) ||
          h.hostname.toLowerCase().contains(q) ||
          h.username.toLowerCase().contains(q) ||
          h.group.toLowerCase().contains(q));
    }
    return out.toList();
  }

  // Duplica un host (con su contraseña): cambiar la IP y listo
  Future<void> _duplicateHost(Host host) async {
    final copy = Host(
      name: '${host.name} (copy)',
      hostname: host.hostname,
      port: host.port,
      username: host.username,
      authType: host.authType,
      keyId: host.keyId,
      startupCmd: host.startupCmd,
      jumpHostId: host.jumpHostId,
      group: host.group,
      useTmux: host.useTmux,
    );
    _hosts.insert(_hosts.indexOf(host) + 1, copy);
    await StorageService.saveHosts(_hosts);
    final pw = await StorageService.getPassword(host.id);
    if (pw != null) await StorageService.savePassword(copy.id, pw);
    await _load();
    _openAddHost(copy); // abrir ya en edición para cambiar IP/nombre
  }

  Color _colorFor(int idx) => _iconColors[idx % _iconColors.length];

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kSurface,
        title: Text(tr('Hosts')),
        actions: [
          // Volver a las sesiones abiertas (con su número)
          ListenableBuilder(
            listenable: TabsHub.instance,
            builder: (_, __) {
              final n = TabsHub.instance.tabs.length;
              if (n == 0) return const SizedBox.shrink();
              return TextButton.icon(
                onPressed: TabsHub.instance.show,
                icon: const Icon(Icons.dvr, size: 18, color: kAccent),
                label: Text('$n',
                    style: const TextStyle(
                        color: kAccent, fontWeight: FontWeight.w600)),
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Barra de búsqueda
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: kTextPri, fontSize: 15),
              decoration: InputDecoration(
                hintText: tr('Search, or "ssh root@ip -p 22"…'),
                prefixIcon: const Icon(Icons.search, color: kTextSec, size: 20),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: kTextSec, size: 18),
                        onPressed: () => _searchCtrl.clear(),
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),

          // Conexión rápida (la búsqueda parece una dirección)
          if (_quickTarget != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Material(
                color: kAccent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _connectDialog(initialAddress: _query),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.bolt, size: 20, color: kAccent),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${tr('Quick connect')}: ${_quickTarget!.user}@'
                            '${_quickTarget!.host}:${_quickTarget!.port}',
                            style: const TextStyle(
                                color: kAccent,
                                fontSize: 14,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                        const Icon(Icons.chevron_right,
                            size: 18, color: kAccent),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Filtro por grupo
          if (_groups.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final g in ['', ..._groups])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(g.isEmpty ? 'All' : g,
                            style: TextStyle(
                                fontSize: 12,
                                color: _groupFilter == g
                                    ? kAccent
                                    : kTextSec)),
                        selected: _groupFilter == g,
                        selectedColor: kAccent.withOpacity(0.18),
                        backgroundColor: kCard,
                        side: BorderSide(
                            color: _groupFilter == g ? kAccent : kDivider),
                        showCheckmark: false,
                        onSelected: (_) =>
                            setState(() => _groupFilter = g),
                      ),
                    ),
                ],
              ),
            ),

          // Lista de hosts (reordenable arrastrando tras pulsación larga,
          // solo sin búsqueda ni filtro de grupo activos)
          Expanded(
            child: filtered.isEmpty
                ? _emptyState()
                : _query.isEmpty && _groupFilter.isEmpty
                    ? ReorderableListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                        itemCount: _hosts.length,
                        onReorder: _reorder,
                        proxyDecorator: (child, _, __) => Material(
                          color: Colors.transparent,
                          elevation: 6,
                          borderRadius: BorderRadius.circular(12),
                          child: child,
                        ),
                        itemBuilder: (_, i) => KeyedSubtree(
                          key: ValueKey(_hosts[i].id),
                          child: _hostCard(_hosts[i], i),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                        itemCount: filtered.length,
                        itemBuilder: (_, i) => _hostCard(filtered[i], i),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showWaysToConnect,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _hostCard(Host host, int idx) {
    final color = _colorFor(_hosts.indexOf(host));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: kCard,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => TabsHub.instance.open(host),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // Icono circular con iniciales
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _initials(host.name),
                    style: TextStyle(
                      color: color,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                // Info del host
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        host.name,
                        style: const TextStyle(
                          color: kTextPri,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${host.username}@${host.hostname}:${host.port}'
                        '${host.jumpHostId != null ? '  ⤷ ${Tr.es ? 'salto' : 'jump'}' : ''}',
                        style: const TextStyle(color: kTextSec, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                if (host.group.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: kAccent2.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      host.group,
                      style: const TextStyle(
                          color: kAccent2,
                          fontSize: 10,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                // Botón auth type
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: kDivider,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    host.authType == 'key' ? 'KEY' : 'PWD',
                    style: TextStyle(
                      color: host.authType == 'key' ? kAccent2 : kTextSec,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Menú
                PopupMenuButton<String>(
                  color: kCard,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  icon: const Icon(Icons.more_vert, color: kTextSec, size: 20),
                  onSelected: (v) {
                    if (v == 'edit') _openAddHost(host);
                    if (v == 'sftp') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => SftpScreen(host: host)),
                      );
                    }
                    if (v == 'duplicate') _duplicateHost(host);
                    if (v == 'delete') _deleteHost(host);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'sftp',
                      child: Row(children: [
                        Icon(Icons.folder_open_outlined,
                            size: 18, color: kTextSec),
                        SizedBox(width: 10),
                        Text(tr('SFTP'), style: TextStyle(color: kTextPri)),
                      ]),
                    ),
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(children: [
                        Icon(Icons.edit_outlined, size: 18, color: kTextSec),
                        SizedBox(width: 10),
                        Text(tr('Edit'), style: TextStyle(color: kTextPri)),
                      ]),
                    ),
                    PopupMenuItem(
                      value: 'duplicate',
                      child: Row(children: [
                        Icon(Icons.copy_outlined, size: 18, color: kTextSec),
                        SizedBox(width: 10),
                        Text(tr('Duplicate'), style: TextStyle(color: kTextPri)),
                      ]),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        Icon(Icons.delete_outline, size: 18, color: kError),
                        SizedBox(width: 10),
                        Text(tr('Delete'), style: TextStyle(color: kError)),
                      ]),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _query.isEmpty ? Icons.dns_outlined : Icons.search_off,
            size: 56,
            color: kTextSec.withOpacity(0.4),
          ),
          const SizedBox(height: 16),
          Text(
            _query.isEmpty
                ? 'No hosts yet'
                : Tr.es ? 'Sin resultados para "$_query"' : 'No results for "$_query"',
            style: const TextStyle(color: kTextSec, fontSize: 16),
          ),
          if (_query.isEmpty) ...[
            const SizedBox(height: 8),
            Text(tr('Tap + to add your first host'),
              style: TextStyle(color: kTextSec, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}
