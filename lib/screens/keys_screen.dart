import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import '../models/ssh_key.dart';
import '../services/i18n.dart';
import '../services/keygen_service.dart';
import '../services/storage_service.dart';

class KeysScreen extends StatefulWidget {
  const KeysScreen({super.key});

  @override
  State<KeysScreen> createState() => _KeysScreenState();
}

class _KeysScreenState extends State<KeysScreen> {
  List<SshKey> _keys = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final keys = await StorageService.getKeys();
    if (mounted) setState(() => _keys = keys);
  }

  Future<void> _importFromFile() async {
    final result =
        await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    final content = String.fromCharCodes(file.bytes!);
    if (!content.contains('PRIVATE KEY')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('The file does not look like a PEM private key')),
        ));
      }
      return;
    }
    await _saveKey(file.name, content);
  }

  Future<void> _pasteKey() async {
    final nameCtrl = TextEditingController();
    final keyCtrl  = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(tr('Paste private key'),
            style: TextStyle(color: kTextPri)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: kTextPri),
                decoration: InputDecoration(labelText: tr('Name')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: keyCtrl,
                maxLines: 8,
                style: const TextStyle(
                    fontSize: 11, fontFamily: 'monospace', color: kTextPri),
                decoration: InputDecoration(
                  labelText: tr('PEM key'),
                  hintText: tr('-----BEGIN OPENSSH PRIVATE KEY-----'),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Cancel'), style: TextStyle(color: kTextSec)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Save'), style: TextStyle(color: kAccent)),
          ),
        ],
      ),
    );
    if (ok == true &&
        nameCtrl.text.isNotEmpty &&
        keyCtrl.text.isNotEmpty) {
      await _saveKey(nameCtrl.text.trim(), keyCtrl.text.trim());
    }
  }

  Future<void> _saveKey(String name, String content, {String? publicKey}) async {
    // Clave protegida: pedir la passphrase, comprobarla y guardarla con la clave
    String? passphrase;
    bool encrypted = false;
    try {
      encrypted = SSHKeyPair.isEncryptedPem(content);
    } catch (_) {}
    if (encrypted) {
      passphrase = await _askPassphrase(name);
      if (passphrase == null) return; // cancelado
      try {
        SSHKeyPair.fromPem(content, passphrase);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(tr('Wrong passphrase: the key cannot be decrypted'))));
        }
        return;
      }
    }
    final key = SshKey(name: name, publicKey: publicKey);
    _keys.add(key);
    await StorageService.saveKeys(_keys);
    await StorageService.saveKeyContent(key.id, content);
    if (passphrase != null) {
      await StorageService.saveKeyPassphrase(key.id, passphrase);
    }
    _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
            Tr.es ? 'Clave "$name" guardada${encrypted ? ' (protegida)' : ''}' : 'Key "$name" saved${encrypted ? ' (protected)' : ''}')),
      );
    }
  }

  Future<String?> _askPassphrase(String name) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(tr('Protected key'),
            style: TextStyle(color: kTextPri, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(Tr.es ? '"$name" está cifrada. La passphrase se guarda en el almacén seguro junto a la clave.' : '"$name" is encrypted. The passphrase is stored in the secure storage next to the key.',
                style: const TextStyle(color: kTextSec, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              obscureText: true,
              autofocus: true,
              style: const TextStyle(color: kTextPri),
              decoration: InputDecoration(labelText: tr('Passphrase')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancel'), style: TextStyle(color: kTextSec)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('OK'), style: TextStyle(color: kAccent)),
          ),
        ],
      ),
    );
    if (ok != true || ctrl.text.isEmpty) return null;
    return ctrl.text;
  }

  Future<void> _generateKey() async {
    final nameCtrl = TextEditingController(text: 'movil');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(tr('Generate ed25519 key'),
            style: TextStyle(color: kTextPri)),
        content: TextField(
          controller: nameCtrl,
          style: const TextStyle(color: kTextPri),
          decoration: InputDecoration(
              labelText: tr('Name (also used as comment)')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Cancel'), style: TextStyle(color: kTextSec)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Generate'), style: TextStyle(color: kAccent)),
          ),
        ],
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) return;
    final name = nameCtrl.text.trim();
    final gen = await KeygenService.generateEd25519('$name@homelab-ssh');
    await _saveKey(name, gen.privatePem, publicKey: gen.publicLine);
    if (mounted) _showPublicKey(name, gen.publicLine);
  }

  void _showPublicKey(String name, String publicLine) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(Tr.es ? 'Clave pública de "$name"' : 'Public key of "$name"',
            style: const TextStyle(color: kTextPri, fontSize: 16)),
        content: SingleChildScrollView(
          child: SelectableText(
            publicLine,
            style: const TextStyle(
                color: kTextSec, fontSize: 11, fontFamily: 'monospace'),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: publicLine));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(tr('Copied. Paste it into ~/.ssh/authorized_keys on the server'))));
            },
            icon: const Icon(Icons.copy, size: 16),
            label: Text(tr('Copy')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Close'), style: TextStyle(color: kTextSec)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteKey(SshKey key) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(tr('Delete key'),
            style: TextStyle(color: kTextPri)),
        content: Text(Tr.es ? '¿Eliminar "${key.name}"?' : 'Delete "${key.name}"?',
            style: const TextStyle(color: kTextSec)),
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
      _keys.removeWhere((k) => k.id == key.id);
      await StorageService.saveKeys(_keys);
      await StorageService.deleteKeyContent(key.id);
      await StorageService.deleteKeyPassphrase(key.id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(tr('SSH keys')),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_fix_high_outlined),
            tooltip: tr('Generate ed25519 key'),
            onPressed: _generateKey,
          ),
          IconButton(
            icon: const Icon(Icons.paste_outlined),
            tooltip: tr('Paste key'),
            onPressed: _pasteKey,
          ),
          IconButton(
            icon: const Icon(Icons.file_open_outlined),
            tooltip: tr('Import file'),
            onPressed: _importFromFile,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _keys.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.vpn_key_outlined,
                      size: 56, color: kTextSec.withOpacity(0.4)),
                  const SizedBox(height: 16),
                  Text(tr('No keys yet'),
                      style: TextStyle(color: kTextSec, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(tr('Use the icons above to import or generate'),
                      style: TextStyle(color: kTextSec, fontSize: 13)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              itemCount: _keys.length,
              itemBuilder: (_, i) {
                final k = _keys[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: kCard,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: kAccent2.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: const Icon(Icons.vpn_key,
                                size: 18, color: kAccent2),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(k.name,
                                    style: const TextStyle(
                                        color: kTextPri,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(
                                    k.publicKey != null
                                        ? 'ed25519 generated in-app'
                                        : 'Private key',
                                    style: const TextStyle(
                                        color: kTextSec, fontSize: 12)),
                              ],
                            ),
                          ),
                          if (k.publicKey != null)
                            IconButton(
                              icon: const Icon(Icons.public,
                                  size: 18, color: kAccent),
                              tooltip: tr('Show public key'),
                              onPressed: () =>
                                  _showPublicKey(k.name, k.publicKey!),
                            ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                size: 18, color: kError),
                            onPressed: () => _deleteKey(k),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
