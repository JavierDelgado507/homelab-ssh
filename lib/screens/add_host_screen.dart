import 'dart:async';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import '../main.dart';
import '../models/host.dart';
import '../models/ssh_key.dart';
import '../services/i18n.dart';
import '../services/storage_service.dart';

class AddHostScreen extends StatefulWidget {
  final Host? host;
  const AddHostScreen({super.key, this.host});

  @override
  State<AddHostScreen> createState() => _AddHostScreenState();
}

class _AddHostScreenState extends State<AddHostScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _hostname;
  late final TextEditingController _port;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _startupCmd;
  late final TextEditingController _group;
  String _authType = 'password';
  String? _selectedKeyId;
  String? _jumpHostId;
  bool _useTmux = false;
  List<SshKey> _keys = [];
  List<Host> _allHosts = [];
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    final h = widget.host;
    _name     = TextEditingController(text: h?.name ?? '');
    _hostname = TextEditingController(text: h?.hostname ?? '');
    _port     = TextEditingController(text: '${h?.port ?? 22}');
    _username = TextEditingController(text: h?.username ?? 'root');
    _password = TextEditingController();
    _startupCmd = TextEditingController(text: h?.startupCmd ?? '');
    _group = TextEditingController(text: h?.group ?? '');
    _authType = h?.authType ?? 'password';
    _selectedKeyId = h?.keyId;
    _jumpHostId = h?.jumpHostId;
    _useTmux = h?.useTmux ?? false;
    _loadKeys();
    StorageService.getHosts().then((hosts) {
      if (mounted) setState(() => _allHosts = hosts);
    });
    if (h != null) {
      StorageService.getPassword(h.id).then((pw) {
        if (pw != null && mounted) _password.text = pw;
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _hostname, _port, _username, _password, _startupCmd, _group]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadKeys() async {
    final keys = await StorageService.getKeys();
    if (mounted) setState(() => _keys = keys);
  }

  bool _testing = false;

  List<String> get _existingGroups {
    final gs = _allHosts
        .map((h) => h.group)
        .where((g) => g.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return gs;
  }

  /// Prueba la conexión con los datos del formulario.
  /// Devuelve null si entra, o el motivo del fallo.
  Future<String?> _testConnection() async {
    SSHSocket? socket;
    SSHClient? client;
    try {
      socket = await SSHSocket.connect(
        _hostname.text.trim(),
        int.tryParse(_port.text) ?? 22,
        timeout: const Duration(seconds: 6),
      );
      if (_authType == 'key') {
        final pem = await StorageService.getKeyContent(_selectedKeyId!);
        if (pem == null) return 'Could not read the SSH key';
        final passphrase =
            await StorageService.getKeyPassphrase(_selectedKeyId!);
        client = SSHClient(socket,
            username: _username.text.trim(),
            identities: SSHKeyPair.fromPem(pem, passphrase));
      } else {
        client = SSHClient(socket,
            username: _username.text.trim(),
            onPasswordRequest: () => _password.text);
      }
      await client.authenticated.timeout(const Duration(seconds: 8));
      return null;
    } on TimeoutException {
      return 'No response (connection timed out)';
    } catch (e) {
      return e.toString().replaceFirst(RegExp(r'^\w*Exception:? ?'), '');
    } finally {
      client?.close();
      socket?.destroy();
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_authType == 'key' && _selectedKeyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Select an SSH key'))),
      );
      return;
    }

    // Probar la conexión antes de guardar (con ProxyJump no se prueba: el
    // host puede no ser alcanzable en directo)
    setState(() => _testing = true);
    final error = _jumpHostId != null ? null : await _testConnection();
    if (!mounted) return;
    setState(() => _testing = false);
    if (error != null) {
      final saveAnyway = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: kSurface,
          title: Text(tr('Could not connect'),
              style: TextStyle(color: kTextPri, fontSize: 17)),
          content: Text(error,
              style: const TextStyle(color: kTextSec, fontSize: 14)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Save anyway'),
                  style: TextStyle(color: kTextSec)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Fix it'),
                  style:
                      TextStyle(color: kAccent, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
      if (saveAnyway != true || !mounted) return;
    }

    final hosts = await StorageService.getHosts();
    final host = Host(
      id: widget.host?.id,
      name: _name.text.trim(),
      hostname: _hostname.text.trim(),
      port: int.tryParse(_port.text) ?? 22,
      username: _username.text.trim(),
      authType: _authType,
      keyId: _authType == 'key' ? _selectedKeyId : null,
      startupCmd: _startupCmd.text.trim(),
      jumpHostId: _jumpHostId,
      group: _group.text.trim(),
      useTmux: _useTmux,
    );
    final idx = hosts.indexWhere((h) => h.id == host.id);
    if (idx >= 0) hosts[idx] = host; else hosts.add(host);
    await StorageService.saveHosts(hosts);
    if (_authType == 'password' && _password.text.isNotEmpty) {
      await StorageService.savePassword(host.id, _password.text);
    }
    if (mounted) Navigator.pop(context, true);
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 10),
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: kAccent,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      );

  Widget _field(
    String label,
    TextEditingController ctrl,
    String hint, {
    TextInputType? keyboardType,
    bool obscure = false,
    Widget? suffix,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl,
        keyboardType: keyboardType,
        obscureText: obscure,
        style: const TextStyle(color: kTextPri),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          suffixIcon: suffix,
        ),
        validator: validator ??
            (v) => (v == null || v.trim().isEmpty) ? tr('Required') : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(tr(widget.host == null ? 'New host' : 'Edit host')),
        actions: [
          TextButton(
            onPressed: _testing ? null : _save,
            child: _testing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: kAccent),
                  )
                : Text(tr('Save'),
                    style:
                        TextStyle(color: kAccent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _section(tr('General')),
              _field(tr('Name'), _name, tr('My Proxmox server')),
              _field(tr('Group (optional)'), _group, 'Proxmox · Docker · Media…',
                  validator: (_) => null),
              if (_existingGroups.isNotEmpty)
                Wrap(
                  spacing: 6,
                  children: _existingGroups
                      .map((g) => ActionChip(
                            label: Text(g,
                                style: const TextStyle(
                                    fontSize: 12, color: kTextPri)),
                            backgroundColor: kCard,
                            side: BorderSide(
                                color: _group.text.trim() == g
                                    ? kAccent
                                    : kDivider),
                            onPressed: () =>
                                setState(() => _group.text = g),
                          ))
                      .toList(),
                ),
              _section(tr('Connection')),
              _field(
                'Hostname / IP',
                _hostname,
                '192.168.1.150',
                keyboardType: TextInputType.url,
              ),
              _field(
                tr('Port'),
                _port,
                '22',
                keyboardType: TextInputType.number,
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  return (n == null || n < 1 || n > 65535)
                      ? tr('Invalid port (1-65535)')
                      : null;
                },
              ),
              _field(tr('User'), _username, 'root'),
              DropdownButtonFormField<String?>(
                value: _jumpHostId,
                dropdownColor: kCard,
                style: const TextStyle(color: kTextPri),
                decoration: InputDecoration(
                    labelText: tr('Connect through (ProxyJump)')),
                items: [
                  DropdownMenuItem<String?>(
                      value: null, child: Text(tr('Direct'))),
                  ..._allHosts
                      .where((x) => x.id != widget.host?.id)
                      .map((x) => DropdownMenuItem<String?>(
                            value: x.id,
                            child: Text('${x.name} (${x.hostname})'),
                          )),
                ],
                onChanged: (v) => setState(() => _jumpHostId = v),
              ),
              const SizedBox(height: 12),
              _section(tr('Authentication')),
              Container(
                decoration: BoxDecoration(
                  color: kCard,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: ['password', 'key'].map((type) {
                    final selected = _authType == type;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _authType = type),
                        child: Container(
                          margin: const EdgeInsets.all(4),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: selected ? kAccent.withOpacity(0.2) : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: selected
                                ? Border.all(color: kAccent.withOpacity(0.5))
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                type == 'key' ? Icons.vpn_key : Icons.lock_outline,
                                size: 16,
                                color: selected ? kAccent : kTextSec,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                tr(type == 'key' ? 'SSH key' : 'Password'),
                                style: TextStyle(
                                  color: selected ? kAccent : kTextSec,
                                  fontSize: 13,
                                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
              if (_authType == 'password')
                _field(
                  tr('Password'),
                  _password,
                  '',
                  obscure: !_showPassword,
                  validator: (_) => null,
                  suffix: IconButton(
                    icon: Icon(
                      _showPassword ? Icons.visibility_off : Icons.visibility,
                      color: kTextSec,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                  ),
                ),
              if (_authType == 'key') ...[
                if (_keys.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: kCard,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(tr('No keys yet. Add one in the Keys tab.'),
                      style: TextStyle(color: kTextSec, fontSize: 13),
                    ),
                  )
                else
                  DropdownButtonFormField<String>(
                    value: _selectedKeyId,
                    dropdownColor: kCard,
                    style: const TextStyle(color: kTextPri),
                    decoration: InputDecoration(labelText: tr('SSH key')),
                    items: _keys
                        .map((k) => DropdownMenuItem(
                              value: k.id,
                              child: Text(k.name),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedKeyId = v),
                  ),
              ],
              _section(tr('On connect')),
              _field(
                tr('Startup command (optional)'),
                _startupCmd,
                'tmux attach  ·  htop  ·  pct enter 100',
                validator: (_) => null,
              ),
              SwitchListTile(
                value: _useTmux,
                activeColor: kAccent,
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Persistent session (tmux)'),
                    style: TextStyle(color: kTextPri, fontSize: 15)),
                subtitle: Text(tr('Reconnect right where you left off. Requires tmux on the server; the startup command runs inside it (only when the session is created).'),
                    style: TextStyle(color: kTextSec, fontSize: 12)),
                onChanged: (v) => setState(() => _useTmux = v),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
