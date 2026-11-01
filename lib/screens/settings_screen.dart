import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';

import '../main.dart';
import '../services/i18n.dart';
import '../services/backup_service.dart';
import '../services/storage_service.dart';
import 'hostkeys_screen.dart';

const kAppVersion = '6.12.0';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _appLock = false;

  @override
  void initState() {
    super.initState();
    StorageService.getAppLock().then((v) {
      if (mounted) setState(() => _appLock = v);
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Biometric lock ──────────────────────────────────────────────────────────
  Future<void> _toggleAppLock(bool enable) async {
    if (enable) {
      try {
        final auth = LocalAuthentication();
        final ok = await auth.authenticate(
          localizedReason: tr('Confirm your identity to enable the lock'),
          options: const AuthenticationOptions(stickyAuth: true),
        );
        if (!ok) return;
      } catch (_) {
        _snack(tr('This device has no fingerprint or PIN configured'));
        return;
      }
    }
    await StorageService.setAppLock(enable);
    if (mounted) setState(() => _appLock = enable);
  }

  // ── Encrypted backups ───────────────────────────────────────────────────────
  Future<String?> _askPassword({required bool confirm}) async {
    final pwCtrl = TextEditingController();
    final pw2Ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(tr(confirm ? 'Encrypt the backup' : 'Backup password'),
            style: const TextStyle(color: kTextPri, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pwCtrl,
              obscureText: true,
              style: const TextStyle(color: kTextPri),
              decoration: InputDecoration(labelText: tr('Password')),
            ),
            if (confirm) ...[
              const SizedBox(height: 12),
              TextField(
                controller: pw2Ctrl,
                obscureText: true,
                style: const TextStyle(color: kTextPri),
                decoration: InputDecoration(labelText: tr('Repeat')),
              ),
            ],
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
    if (ok != true || pwCtrl.text.isEmpty) return null;
    if (confirm && pwCtrl.text != pw2Ctrl.text) {
      _snack(tr('Passwords do not match'));
      return null;
    }
    return pwCtrl.text;
  }

  Future<void> _exportBackup() async {
    final pw = await _askPassword(confirm: true);
    if (pw == null) return;
    try {
      final bytes = await BackupService.export(pw);
      final dir = await getTemporaryDirectory();
      final date = DateTime.now().toIso8601String().substring(0, 10);
      final name = 'homelab-ssh-backup-$date.hssh';
      final f = File('${dir.path}/$name');
      await f.writeAsBytes(bytes);
      final saved = await FlutterFileDialog.saveFile(
          params: SaveFileDialogParams(sourceFilePath: f.path, fileName: name));
      await f.delete();
      _snack(tr(saved != null
          ? 'Backup saved (hosts, keys, passwords and snippets)'
          : 'Export cancelled'));
    } catch (e) {
      _snack('${Tr.es ? 'Error al exportar' : 'Export failed'}: $e');
    }
  }

  Future<void> _importBackup() async {
    final res = await FilePicker.platform.pickFiles(withData: true);
    if (res == null || res.files.isEmpty || res.files.first.bytes == null) {
      return;
    }
    final pw = await _askPassword(confirm: false);
    if (pw == null) return;
    try {
      final n = await BackupService.import(res.files.first.bytes!, pw);
      _snack(Tr.es ? 'Copia restaurada ($n entradas)' : 'Backup restored ($n entries)');
    } on FormatException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack(tr('Wrong password or corrupted backup'));
    }
  }

  Widget _tile(IconData icon, Color color, String title, String subtitle,
      VoidCallback onTap, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: kCard,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              color: kTextPri,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: const TextStyle(
                              color: kTextSec, fontSize: 12)),
                    ],
                  ),
                ),
                trailing ??
                    const Icon(Icons.chevron_right,
                        color: kTextSec, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(title: Text(tr('Settings'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          _tile(
            Icons.fingerprint,
            kAccent,
            tr('Biometric lock'),
            tr('Ask for fingerprint or PIN when opening the app'),
            () => _toggleAppLock(!_appLock),
            trailing: Switch(
              value: _appLock,
              activeColor: kAccent,
              onChanged: _toggleAppLock,
            ),
          ),
          _tile(
            Icons.save_alt,
            kAccent2,
            tr('Export backup'),
            tr('Hosts, keys, passwords and snippets in an encrypted file'),
            _exportBackup,
          ),
          _tile(
            Icons.settings_backup_restore,
            kAccent2,
            tr('Import backup'),
            tr('Restore an encrypted .hssh backup'),
            _importBackup,
          ),
          _tile(
            Icons.dns_outlined,
            const Color(0xFF6BCB77),
            tr('Server fingerprints'),
            tr('Known host keys (trust on first use)'),
            () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const HostkeysScreen())),
          ),
          _tile(
            Icons.translate,
            kAccent,
            tr('Language'),
            Tr.es ? 'Español' : 'English',
            () async {
              await Tr.set(Tr.es ? 'en' : 'es');
              if (mounted) setState(() {});
            },
          ),
          _tile(
            Icons.info_outline,
            const Color(0xFFFFD93D),
            tr('About'),
            'Homelab SSH $kAppVersion · open-source licenses',
            () => showLicensePage(
              context: context,
              applicationName: 'Homelab SSH',
              applicationVersion: kAppVersion,
              applicationLegalese:
                  'MIT License · © 2026 Javier Delgado\n'
                  'An SSH client built for homelabs.',
            ),
          ),
        ],
      ),
    );
  }
}
