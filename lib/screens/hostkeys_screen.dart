import 'package:flutter/material.dart';
import '../main.dart';
import '../services/i18n.dart';
import '../services/storage_service.dart';

/// Gestor de huellas TOFU: lista "host:puerto → huella" con opción de borrar
/// (p. ej. tras reinstalar un servidor, para que la próxima conexión vuelva a
/// registrarla sin el aviso rojo).
class HostkeysScreen extends StatefulWidget {
  const HostkeysScreen({super.key});

  @override
  State<HostkeysScreen> createState() => _HostkeysScreenState();
}

class _HostkeysScreenState extends State<HostkeysScreen> {
  Map<String, String> _keys = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final keys = await StorageService.getAllHostkeys();
    if (mounted) setState(() { _keys = keys; _loading = false; });
  }

  Future<void> _delete(String hostPort) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(tr('Forget fingerprint'), style: TextStyle(color: kTextPri)),
        content: Text(
          'Forget the fingerprint of $hostPort?\n\nThe next connection '
          'will record it again without warning.',
          style: const TextStyle(color: kTextSec, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancel'), style: TextStyle(color: kTextSec)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Forget'), style: TextStyle(color: kError)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await StorageService.deleteHostkey(hostPort);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _keys.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(tr('Server fingerprints')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: kTextSec),
            onPressed: _load,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kAccent))
          : entries.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.fingerprint,
                          size: 56, color: kTextSec.withOpacity(0.4)),
                      const SizedBox(height: 16),
                      Text(tr('No fingerprints yet'),
                          style: TextStyle(color: kTextSec, fontSize: 16)),
                      const SizedBox(height: 8),
                      Text(tr('They are recorded the first time you connect'),
                          style: TextStyle(color: kTextSec, fontSize: 13)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  itemCount: entries.length,
                  itemBuilder: (_, i) {
                    final e = entries[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: kCard,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              const Icon(Icons.fingerprint,
                                  size: 20, color: kAccent),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(e.key,
                                        style: const TextStyle(
                                            color: kTextPri,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 2),
                                    Text(e.value,
                                        style: const TextStyle(
                                            color: kTextSec,
                                            fontSize: 10,
                                            fontFamily: 'monospace')),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 18, color: kError),
                                tooltip: tr('Forget fingerprint'),
                                onPressed: () => _delete(e.key),
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
