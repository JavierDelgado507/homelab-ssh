import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'storage_service.dart';

/// Copia de seguridad cifrada de todo el almacén (hosts, contraseñas, claves
/// privadas, snippets y huellas TOFU). Formato del fichero .hssh:
///   "HSSH1" + salt(16) + nonce(12) + AES-256-GCM(json) + tag(16)
/// La clave sale de la contraseña con PBKDF2-HMAC-SHA256 (150 000 iteraciones).
class BackupService {
  static const _magic = 'HSSH1';
  static const _iterations = 150000;

  static final _aes = AesGcm.with256bits();

  static Future<SecretKey> _deriveKey(String password, List<int> salt) {
    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _iterations,
      bits: 256,
    );
    return kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
  }

  static Future<Uint8List> export(String password) async {
    final data = await StorageService.dumpAll();
    return encryptPayload(data, password);
  }

  /// Cifra un volcado clave→valor (pura: sin tocar el almacén; testeable).
  static Future<Uint8List> encryptPayload(
      Map<String, String> data, String password) async {
    final plain = utf8.encode(jsonEncode(data));

    final rnd = Random.secure();
    final salt = List<int>.generate(16, (_) => rnd.nextInt(256));
    final key = await _deriveKey(password, salt);

    final box = await _aes.encrypt(plain, secretKey: key);

    final out = BytesBuilder();
    out.add(ascii.encode(_magic));
    out.add(salt);
    out.add(box.nonce);           // 12 bytes
    out.add(box.cipherText);
    out.add(box.mac.bytes);       // 16 bytes
    return out.takeBytes();
  }

  /// Devuelve cuántas entradas se han restaurado.
  /// Lanza [FormatException] si el fichero no es válido y
  /// [SecretBoxAuthenticationError] si la contraseña es incorrecta.
  static Future<int> import(Uint8List bytes, String password) async {
    final data = await decryptPayload(bytes, password);
    await StorageService.restoreAll(data);
    return data.length;
  }

  /// Descifra una copia (pura). Lanza [FormatException] si el fichero no es
  /// válido y error de autenticación AES si la contraseña no es la buena.
  static Future<Map<String, String>> decryptPayload(
      Uint8List bytes, String password) async {
    if (bytes.length < 5 + 16 + 12 + 16 ||
        ascii.decode(bytes.sublist(0, 5)) != _magic) {
      throw const FormatException('Not a Homelab SSH backup');
    }
    final salt = bytes.sublist(5, 21);
    final nonce = bytes.sublist(21, 33);
    final cipherText = bytes.sublist(33, bytes.length - 16);
    final mac = bytes.sublist(bytes.length - 16);

    final key = await _deriveKey(password, salt);
    final plain = await _aes.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
      secretKey: key,
    );

    return (jsonDecode(utf8.decode(plain)) as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, v as String));
  }
}
