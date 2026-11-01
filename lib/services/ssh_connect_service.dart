import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/host.dart';
import 'i18n.dart';
import 'storage_service.dart';

/// Traduce las excepciones típicas de una conexión SSH a un mensaje claro.
String humanizeSshError(Object e) {
  final msg = e.toString();
  final low = msg.toLowerCase();
  if (low.contains('timed out') || low.contains('timeout')) {
    return tr('No response (connection timed out)');
  }
  if (low.contains('refused')) {
    return tr('Connection refused (is SSH listening on that port?)');
  }
  if (low.contains('failed host lookup') || low.contains('name or service')) {
    return tr('Hostname not found');
  }
  if (low.contains('unreachable') || low.contains('no route')) {
    return tr('Host unreachable (check the network)');
  }
  if (low.contains('hostkey')) {
    return tr('Host key rejected');
  }
  if (low.contains('auth')) {
    return tr('Authentication failed (wrong password or key)');
  }
  return msg.replaceFirst(RegExp(r'^\w*Exception:? ?'), '');
}

/// Pregunta al usuario qué hacer cuando la huella guardada no coincide.
/// Devuelve true para confiar y actualizar la huella.
typedef HostkeyPrompt = Future<bool> Function(
    Host h, String stored, String current);

/// Una conexión SSH completa: el cliente final y los clientes intermedios de
/// la cadena ProxyJump (hay que cerrarlos todos).
class SshConnection {
  final SSHClient client;
  final SSHSocket socket;
  final List<SSHClient> jumpClients;
  SshConnection(this.client, this.socket, this.jumpClients);

  void close() {
    try { client.close(); } catch (_) {}
    for (final c in jumpClients) {
      try { c.close(); } catch (_) {}
    }
  }
}

/// Lógica de conexión compartida por el terminal y el SFTP directo:
/// TOFU de huellas, auth por clave (con passphrase) o contraseña, y
/// ProxyJump recursivo con protección frente a ciclos.
class SshConnectService {
  static Future<SshConnection> connect(
    Host h, {
    required HostkeyPrompt onHostkeyMismatch,
    void Function(String msg)? onInfo,
  }) async {
    final jumps = <SSHClient>[];
    try {
      final all = h.jumpHostId != null
          ? await StorageService.getHosts()
          : const <Host>[];
      final socket = await _socketFor(
          h, all, {h.id}, jumps, onHostkeyMismatch, onInfo);
      final client = await _buildClient(h, socket, onHostkeyMismatch);
      return SshConnection(client, socket, jumps);
    } catch (_) {
      for (final c in jumps) {
        try { c.close(); } catch (_) {}
      }
      rethrow;
    }
  }

  static Future<SSHSocket> _socketFor(
    Host h,
    List<Host> all,
    Set<String> visited,
    List<SSHClient> jumps,
    HostkeyPrompt onMismatch,
    void Function(String)? onInfo,
  ) async {
    final jumpId = h.jumpHostId;
    if (jumpId == null || visited.contains(jumpId) || visited.length > 3) {
      return SSHSocket.connect(h.hostname, h.port,
          timeout: const Duration(seconds: 8));
    }
    final idx = all.indexWhere((x) => x.id == jumpId);
    if (idx < 0) {
      return SSHSocket.connect(h.hostname, h.port,
          timeout: const Duration(seconds: 8));
    }
    final jump = all[idx];
    visited.add(jump.id);
    onInfo?.call('Jumping through ${jump.name} (${jump.hostname})…');
    final jumpSocket =
        await _socketFor(jump, all, visited, jumps, onMismatch, onInfo);
    final jumpClient = await _buildClient(jump, jumpSocket, onMismatch,
        onInfo: onInfo);
    jumps.add(jumpClient);
    return jumpClient.forwardLocal(h.hostname, h.port);
  }

  static Future<SSHClient> _buildClient(
    Host h,
    SSHSocket socket,
    HostkeyPrompt onMismatch, {
    void Function(String)? onInfo,
  }) async {
    verify(String t, Uint8List fp) => _verifyHostKey(h, t, fp, onMismatch, onInfo);
    if (h.authType == 'key') {
      final pem = await StorageService.getKeyContent(h.keyId!);
      if (pem == null) throw Exception('SSH key not found');
      final passphrase = await StorageService.getKeyPassphrase(h.keyId!);
      return SSHClient(socket,
          username: h.username,
          identities: SSHKeyPair.fromPem(pem, passphrase),
          onVerifyHostKey: verify,
          keepAliveInterval: const Duration(seconds: 15));
    }
    final pw = await StorageService.getPassword(h.id) ?? '';
    return SSHClient(socket,
        username: h.username,
        onPasswordRequest: () => pw,
        onVerifyHostKey: verify,
        keepAliveInterval: const Duration(seconds: 15));
  }

  // TOFU: la primera huella se guarda sin preguntar; si cambia, decide el
  // callback (que normalmente enseña un diálogo).
  static Future<bool> _verifyHostKey(
    Host h,
    String type,
    Uint8List fingerprint,
    HostkeyPrompt onMismatch,
    void Function(String)? onInfo,
  ) async {
    final id = '${h.hostname}:${h.port}';
    final hex = fingerprint
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(':');
    final current = '$type $hex';
    final stored = await StorageService.getHostkey(id);
    if (stored == null) {
      await StorageService.saveHostkey(id, current);
      onInfo?.call('Fingerprint of $id recorded: $current');
      return true;
    }
    if (stored == current) return true;
    final ok = await onMismatch(h, stored, current);
    if (ok) await StorageService.saveHostkey(id, current);
    return ok;
  }

  /// Diálogo estándar de huella cambiada (lo usan terminal y SFTP).
  static Future<bool> showMismatchDialog(
      BuildContext context, Host h, String stored, String current) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(tr('⚠ Server fingerprint has changed'),
            style: TextStyle(color: kError, fontSize: 16)),
        content: Text(
          'The identity of ${h.hostname}:${h.port} does not match the '
          'stored one.\n\nStored:\n$stored\n\nReceived:\n$current\n\n'
          'If you did not reinstall the server, this could be an attack.',
          style: const TextStyle(
              color: kTextSec, fontSize: 12, fontFamily: 'monospace'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancel'),
                style: TextStyle(color: kAccent, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Trust and update'),
                style: TextStyle(color: kError)),
          ),
        ],
      ),
    );
    return ok == true;
  }
}
