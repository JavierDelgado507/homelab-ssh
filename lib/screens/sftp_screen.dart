import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:path_provider/path_provider.dart';
import '../main.dart';
import '../models/host.dart';
import '../services/i18n.dart';
import '../services/i18n.dart';
import '../services/ssh_connect_service.dart';

/// Explorador SFTP. Se puede abrir de dos formas:
/// - con [client]: reutiliza la sesión SSH de un terminal ya conectado
/// - con [host]: conexión propia (menú del host en Keychain), se cierra al salir
class SftpScreen extends StatefulWidget {
  final SSHClient? client;
  final Host? host;
  const SftpScreen({super.key, this.client, this.host})
      : assert(client != null || host != null);

  @override
  State<SftpScreen> createState() => _SftpScreenState();
}

class _SftpScreenState extends State<SftpScreen> {
  late SftpClient _sftp;
  SshConnection? _ownConn; // conexión propia (modo host), hay que cerrarla
  String _currentPath = '/';
  List<SftpName> _items = [];
  bool _loading = true;
  String? _error;
  final List<String> _pathStack = ['/'];
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _ownConn?.close();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      SSHClient client;
      if (widget.client != null) {
        client = widget.client!;
      } else {
        _ownConn = await SshConnectService.connect(
          widget.host!,
          onHostkeyMismatch: (h, stored, current) => mounted
              ? SshConnectService.showMismatchDialog(
                  context, h, stored, current)
              : Future.value(false),
        );
        client = _ownConn!.client;
      }
      _sftp = await client.sftp();
      _initialized = true;
      await _listDir('/');
    } catch (e) {
      if (mounted) {
        setState(() { _error = humanizeSshError(e); _loading = false; });
      }
    }
  }

  Future<void> _listDir(String path) async {
    if (!_initialized) return;
    setState(() { _loading = true; _error = null; });
    try {
      final items = await _sftp.listdir(path);
      items.sort((a, b) {
        if (a.attr.isDirectory != b.attr.isDirectory) {
          return a.attr.isDirectory ? -1 : 1;
        }
        return a.filename.compareTo(b.filename);
      });
      setState(() {
        _currentPath = path;
        _items = items.where((i) => i.filename != '.').toList();
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _navigate(SftpName item) {
    if (!item.attr.isDirectory) return;
    if (item.filename == '..') {
      if (_pathStack.length > 1) {
        _pathStack.removeLast();
        _listDir(_pathStack.last);
      }
      return;
    }
    final newPath = _currentPath == '/'
        ? '/${item.filename}'
        : '$_currentPath/${item.filename}';
    _pathStack.add(newPath);
    _listDir(newPath);
  }

  String _remotePath(String filename) =>
      _currentPath == '/' ? '/$filename' : '$_currentPath/$filename';

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor:
          error ? kError.withOpacity(0.2) : kSuccess.withOpacity(0.2),
    ));
  }

  /// Diálogo de progreso. [progress] va de 0 a 1; null = indeterminado.
  ValueNotifier<double?>? _progress;

  void _showProgress(String title) {
    _progress = ValueNotifier<double?>(null);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(title,
            style: const TextStyle(color: kTextPri, fontSize: 15)),
        content: ValueListenableBuilder<double?>(
          valueListenable: _progress!,
          builder: (_, v, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: v,
                color: kAccent,
                backgroundColor: kDivider,
              ),
              const SizedBox(height: 10),
              Text(
                v == null ? '…' : '${(v * 100).toStringAsFixed(0)} %',
                style: const TextStyle(color: kTextSec, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _hideProgress() {
    if (_progress != null && mounted) Navigator.pop(context);
    _progress = null;
  }

  // Descarga por streaming a un temporal y después deja elegir dónde guardarlo
  // (Descargas por defecto) con el diálogo del sistema.
  Future<void> _downloadFile(SftpName item) async {
    final remotePath = _remotePath(item.filename);
    final total = item.attr.size ?? 0;
    _showProgress('${Tr.es ? 'Descargando' : 'Downloading'} ${item.filename}');
    File? tmp;
    try {
      final file = await _sftp.open(remotePath, mode: SftpFileOpenMode.read);
      final dir = await getTemporaryDirectory();
      tmp = File('${dir.path}/${item.filename}');
      final sink = tmp.openWrite();
      var done = 0;
      await for (final chunk in file.read()) {
        sink.add(chunk);
        done += chunk.length;
        if (total > 0) _progress?.value = done / total;
      }
      await sink.close();
      await file.close();
      _hideProgress();

      final saved = await FlutterFileDialog.saveFile(
        params: SaveFileDialogParams(
          sourceFilePath: tmp.path,
          fileName: item.filename,
        ),
      );
      _snack(saved != null
          ? '✓ ${item.filename} ${Tr.es ? 'guardado' : 'saved'}'
          : tr('Download cancelled'));
    } catch (e) {
      _hideProgress();
      _snack('Error: $e', error: true);
    } finally {
      try { await tmp?.delete(); } catch (_) {}
    }
  }

  // Sube desde la ruta local en streaming (sin cargar el fichero en RAM).
  Future<void> _uploadFile() async {
    final result = await FilePicker.platform.pickFiles(withData: false);
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    final localPath = picked.path;
    if (localPath == null) return;

    final remotePath = _remotePath(picked.name);
    final local = File(localPath);
    final total = await local.length();
    _showProgress('${Tr.es ? 'Subiendo' : 'Uploading'} ${picked.name}');
    try {
      final file = await _sftp.open(
        remotePath,
        mode: SftpFileOpenMode.write |
            SftpFileOpenMode.create |
            SftpFileOpenMode.truncate,
      );
      var done = 0;
      final stream = local.openRead().map((chunk) {
        done += chunk.length;
        if (total > 0) _progress?.value = done / total;
        return Uint8List.fromList(chunk);
      });
      await file.write(stream);
      await file.close();
      _hideProgress();
      await _listDir(_currentPath);
      _snack('✓ ${picked.name} ${Tr.es ? 'subido' : 'uploaded'}');
    } catch (e) {
      _hideProgress();
      _snack('Upload failed: $e', error: true);
    }
  }

  // ── Operaciones de fichero (pulsación larga) ───────────────────────────────
  Future<void> _mkdir() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(tr('New folder'), style: TextStyle(color: kTextPri)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: kTextPri),
          decoration: InputDecoration(labelText: tr('Name')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancel'), style: TextStyle(color: kTextSec)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Create'), style: TextStyle(color: kAccent)),
          ),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    try {
      await _sftp.mkdir(_remotePath(ctrl.text.trim()));
      await _listDir(_currentPath);
    } catch (e) {
      _snack('Error: $e', error: true);
    }
  }

  Future<void> _renameItem(SftpName item) async {
    final ctrl = TextEditingController(text: item.filename);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(tr('Rename'), style: TextStyle(color: kTextPri)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: kTextPri),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancel'), style: TextStyle(color: kTextSec)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Rename'), style: TextStyle(color: kAccent)),
          ),
        ],
      ),
    );
    final newName = ctrl.text.trim();
    if (ok != true || newName.isEmpty || newName == item.filename) return;
    try {
      await _sftp.rename(_remotePath(item.filename), _remotePath(newName));
      await _listDir(_currentPath);
    } catch (e) {
      _snack('Error: $e', error: true);
    }
  }

  Future<void> _deleteItem(SftpName item) async {
    final isDir = item.attr.isDirectory;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(tr(isDir ? 'Delete folder' : 'Delete file'),
            style: const TextStyle(color: kTextPri)),
        content: Text(
          Tr.es
              ? '¿Eliminar "${item.filename}"?${isDir ? ' (solo si está vacía)' : ''}'
              : 'Delete "${item.filename}"?${isDir ? ' (only if empty)' : ''}',
          style: const TextStyle(color: kTextSec),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancel'), style: TextStyle(color: kTextSec)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Delete'), style: TextStyle(color: kError)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      if (isDir) {
        await _sftp.rmdir(_remotePath(item.filename));
      } else {
        await _sftp.remove(_remotePath(item.filename));
      }
      await _listDir(_currentPath);
    } catch (e) {
      _snack('Error: $e', error: true);
    }
  }

  void _showItemMenu(SftpName item) {
    if (item.filename == '..') return;
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
            ListTile(
              leading: Icon(_iconFor(item), color: _colorFor(item), size: 20),
              title: Text(item.filename,
                  style: const TextStyle(color: kTextPri, fontSize: 14)),
              subtitle: item.attr.isDirectory
                  ? null
                  : Text(_formatSize(item.attr.size),
                      style: const TextStyle(color: kTextSec, fontSize: 11)),
            ),
            const Divider(height: 1, color: kDivider),
            if (!item.attr.isDirectory)
              ListTile(
                leading: const Icon(Icons.download_outlined,
                    color: kAccent, size: 20),
                title: Text(tr('Download'),
                    style: TextStyle(color: kTextPri)),
                onTap: () {
                  Navigator.pop(ctx);
                  _downloadFile(item);
                },
              ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline,
                  color: kAccent2, size: 20),
              title:
                  Text(tr('Rename'), style: TextStyle(color: kTextPri)),
              onTap: () {
                Navigator.pop(ctx);
                _renameItem(item);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: kError, size: 20),
              title: Text(tr('Delete'), style: TextStyle(color: kError)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteItem(item);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _formatSize(int? size) {
    if (size == null || size == 0) return '';
    if (size < 1024) return '$size B';
    if (size < 1048576) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1073741824) return '${(size / 1048576).toStringAsFixed(1)} MB';
    return '${(size / 1073741824).toStringAsFixed(1)} GB';
  }

  IconData _iconFor(SftpName item) {
    if (item.attr.isDirectory) return Icons.folder;
    final ext = item.filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'txt': case 'log': case 'conf': case 'yml': case 'yaml':
      case 'json': case 'sh': case 'py': case 'js': case 'ts':
        return Icons.description_outlined;
      case 'zip': case 'tar': case 'gz': case 'bz2': case 'xz':
        return Icons.folder_zip_outlined;
      case 'png': case 'jpg': case 'jpeg': case 'gif': case 'webp':
        return Icons.image_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  Color _colorFor(SftpName item) {
    if (item.attr.isDirectory) return const Color(0xFFFFD93D);
    final ext = item.filename.split('.').last.toLowerCase();
    if (['sh', 'py', 'js', 'ts', 'rb'].contains(ext)) return kAccent2;
    if (['zip', 'tar', 'gz'].contains(ext)) return kAccent;
    if (['png', 'jpg', 'jpeg', 'gif'].contains(ext)) return const Color(0xFF6BCB77);
    return kTextSec;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kSurface,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                widget.host != null
                    ? 'SFTP — ${widget.host!.name}'
                    : 'SFTP',
                style: const TextStyle(fontSize: 16)),
            Text(
              _currentPath,
              style: const TextStyle(fontSize: 11, color: kTextSec),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined, color: kTextSec),
            tooltip: tr('New folder'),
            onPressed: _mkdir,
          ),
          IconButton(
            icon: const Icon(Icons.upload_file_outlined, color: kTextSec),
            tooltip: tr('Upload file'),
            onPressed: _uploadFile,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: kTextSec),
            onPressed: () => _listDir(_currentPath),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: kAccent),
            )
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: kError),
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: const TextStyle(color: kTextSec),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: kCard),
                        onPressed: () {
                          if (_initialized) {
                            _listDir(_currentPath);
                          } else {
                            setState(() { _loading = true; _error = null; });
                            _init();
                          }
                        },
                        child: Text(tr('Retry')),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final item = _items[i];
                    final isDir = item.attr.isDirectory;
                    final color = _colorFor(item);
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () =>
                            isDir ? _navigate(item) : _showItemMenu(item),
                        onLongPress: () => _showItemMenu(item),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          child: Row(
                            children: [
                              Icon(_iconFor(item), size: 20, color: color),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.filename,
                                      style: const TextStyle(
                                          color: kTextPri, fontSize: 14),
                                    ),
                                    if (!isDir &&
                                        item.attr.size != null &&
                                        item.attr.size! > 0)
                                      Text(
                                        _formatSize(item.attr.size),
                                        style: const TextStyle(
                                            color: kTextSec, fontSize: 11),
                                      ),
                                  ],
                                ),
                              ),
                              if (isDir)
                                const Icon(Icons.chevron_right,
                                    color: kTextSec, size: 18)
                              else
                                IconButton(
                                  icon: const Icon(Icons.download_outlined,
                                      size: 18, color: kTextSec),
                                  onPressed: () => _downloadFile(item),
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
