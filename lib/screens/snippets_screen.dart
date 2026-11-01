import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../main.dart';
import '../services/i18n.dart';

class Snippet {
  String id;
  String name;
  String command;
  Snippet({required this.id, required this.name, required this.command});

  factory Snippet.fromJson(Map<String, dynamic> j) =>
      Snippet(id: j['id'], name: j['name'], command: j['command']);
  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'command': command};
}

class SnippetsScreen extends StatefulWidget {
  // true → al tocar un snippet se devuelve su comando (abierto desde un
  // terminal); false → pestaña de gestión: tocar edita.
  final bool selectMode;
  const SnippetsScreen({super.key, this.selectMode = false});

  @override
  State<SnippetsScreen> createState() => _SnippetsScreenState();
}

class _SnippetsScreenState extends State<SnippetsScreen> {
  static const _storage =
      FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

  List<Snippet> _snippets = [];

  @override
  void initState() {
    super.initState();
    _load();
    kDataChanged.addListener(_load);
  }

  @override
  void dispose() {
    kDataChanged.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final raw = await _storage.read(key: 'snippets');
    if (raw == null) {
      setState(() => _snippets = _defaults());
      return;
    }
    final list = jsonDecode(raw) as List;
    if (mounted) {
      setState(() => _snippets =
          list.map((e) => Snippet.fromJson(e as Map<String, dynamic>)).toList());
    }
  }

  List<Snippet> _defaults() => [
        Snippet(id: 's1', name: tr('Processes'), command: 'ps aux\n'),
        Snippet(id: 's2', name: tr('Disk usage'),   command: 'df -h\n'),
        Snippet(id: 's3', name: tr('Memory'),       command: 'free -h\n'),
        Snippet(id: 's4', name: tr('System log'),   command: 'journalctl -n 50 --no-pager\n'),
        Snippet(id: 's5', name: 'Docker ps',    command: 'docker ps\n'),
        Snippet(id: 's6', name: tr('Upgrade'),      command: 'apt-get update && apt-get upgrade -y\n'),
      ];

  Future<void> _save() async {
    await _storage.write(
      key: 'snippets',
      value: jsonEncode(_snippets.map((s) => s.toJson()).toList()),
    );
  }

  Future<void> _addOrEdit([Snippet? existing]) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final cmdCtrl  = TextEditingController(text: existing?.command ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          existing == null ? 'New snippet' : 'Edit snippet',
          style: const TextStyle(color: kTextPri),
        ),
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
                controller: cmdCtrl,
                maxLines: 4,
                style: const TextStyle(
                    fontSize: 13, fontFamily: 'monospace', color: kTextPri),
                decoration: InputDecoration(
                  labelText: tr('Command'),
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
    if (ok != true) return;
    if (existing == null) {
      _snippets.add(Snippet(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: nameCtrl.text.trim(),
        command: cmdCtrl.text,
      ));
    } else {
      existing.name = nameCtrl.text.trim();
      existing.command = cmdCtrl.text;
    }
    await _save();
    if (mounted) setState(() {});
  }

  Future<void> _delete(Snippet s) async {
    _snippets.removeWhere((e) => e.id == s.id);
    await _save();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(tr('Snippets')),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _addOrEdit(),
          ),
        ],
      ),
      body: _snippets.isEmpty
          ? Center(
              child: Text(tr('No snippets. Tap + to add one.'),
                  style: const TextStyle(color: kTextSec)))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
              itemCount: _snippets.length,
              itemBuilder: (_, i) {
                final s = _snippets[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: kCard,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => widget.selectMode
                          ? Navigator.pop(context, s.command)
                          : _addOrEdit(s),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            const Icon(Icons.code, size: 18, color: kAccent2),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.name,
                                      style: const TextStyle(
                                          color: kTextPri,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 2),
                                  Text(
                                    s.command.trim(),
                                    style: const TextStyle(
                                        color: kTextSec,
                                        fontSize: 12,
                                        fontFamily: 'monospace'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined,
                                  size: 17, color: kTextSec),
                              onPressed: () => _addOrEdit(s),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  size: 17, color: kError),
                              onPressed: () => _delete(s),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
