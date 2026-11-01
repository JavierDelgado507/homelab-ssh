import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/host.dart';
import '../models/ssh_key.dart';

class StorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static Future<List<Host>> getHosts() async {
    final raw = await _storage.read(key: 'hosts');
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => Host.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<void> saveHosts(List<Host> hosts) async {
    await _storage.write(
      key: 'hosts',
      value: jsonEncode(hosts.map((h) => h.toJson()).toList()),
    );
  }

  static Future<String?> getPassword(String hostId) =>
      _storage.read(key: 'pw_$hostId');

  static Future<void> savePassword(String hostId, String pw) =>
      _storage.write(key: 'pw_$hostId', value: pw);

  static Future<void> deletePassword(String hostId) =>
      _storage.delete(key: 'pw_$hostId');

  static Future<List<SshKey>> getKeys() async {
    final raw = await _storage.read(key: 'keys');
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => SshKey.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<void> saveKeys(List<SshKey> keys) async {
    await _storage.write(
      key: 'keys',
      value: jsonEncode(keys.map((k) => k.toJson()).toList()),
    );
  }

  static Future<String?> getKeyContent(String keyId) =>
      _storage.read(key: 'key_$keyId');

  static Future<void> saveKeyContent(String keyId, String content) =>
      _storage.write(key: 'key_$keyId', value: content);

  static Future<void> deleteKeyContent(String keyId) =>
      _storage.delete(key: 'key_$keyId');

  // ── Huellas de host (TOFU: se guarda la primera y se compara después) ──────
  static Future<String?> getHostkey(String hostPort) =>
      _storage.read(key: 'hk_$hostPort');

  static Future<void> saveHostkey(String hostPort, String fingerprint) =>
      _storage.write(key: 'hk_$hostPort', value: fingerprint);

  static Future<void> deleteHostkey(String hostPort) =>
      _storage.delete(key: 'hk_$hostPort');

  /// Todas las huellas guardadas: "host:puerto" → "tipo md5:…"
  static Future<Map<String, String>> getAllHostkeys() async {
    final all = await _storage.readAll();
    return {
      for (final e in all.entries)
        if (e.key.startsWith('hk_')) e.key.substring(3): e.value,
    };
  }

  // ── Passphrase de claves privadas cifradas ─────────────────────────────────
  static Future<String?> getKeyPassphrase(String keyId) =>
      _storage.read(key: 'kp_$keyId');

  static Future<void> saveKeyPassphrase(String keyId, String passphrase) =>
      _storage.write(key: 'kp_$keyId', value: passphrase);

  static Future<void> deleteKeyPassphrase(String keyId) =>
      _storage.delete(key: 'kp_$keyId');

  // ── Historial de comandos (para el autocompletado del terminal) ────────────
  static Future<List<String>> getCmdHistory() async {
    final raw = await _storage.read(key: 'cmd_history');
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<String>();
  }

  static Future<void> saveCmdHistory(List<String> history) =>
      _storage.write(
          key: 'cmd_history', value: jsonEncode(history.take(200).toList()));

  // ── Preferencias del terminal ──────────────────────────────────────────────
  static Future<double?> getFontSize() async {
    final raw = await _storage.read(key: 'font_size');
    return raw == null ? null : double.tryParse(raw);
  }

  static Future<void> saveFontSize(double size) =>
      _storage.write(key: 'font_size', value: size.toString());

  static Future<String?> getTermTheme() => _storage.read(key: 'term_theme');

  static Future<void> saveTermTheme(String name) =>
      _storage.write(key: 'term_theme', value: name);

  // ── Idioma de la interfaz ('en' | 'es') ────────────────────────────────────
  static Future<String?> getLang() => _storage.read(key: 'lang');

  static Future<void> setLang(String lang) =>
      _storage.write(key: 'lang', value: lang);

  // ── Bloqueo biométrico al abrir la app ─────────────────────────────────────
  static Future<bool> getAppLock() async =>
      (await _storage.read(key: 'app_lock')) == '1';

  static Future<void> setAppLock(bool enabled) =>
      _storage.write(key: 'app_lock', value: enabled ? '1' : '0');

  // ── Volcado completo (para exportar/importar copias de seguridad) ──────────
  static Future<Map<String, String>> dumpAll() => _storage.readAll();

  static Future<void> restoreAll(Map<String, String> data) async {
    for (final e in data.entries) {
      await _storage.write(key: e.key, value: e.value);
    }
  }
}
