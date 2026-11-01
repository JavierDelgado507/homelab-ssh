import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class GeneratedKey {
  final String privatePem; // formato openssh-key-v1 sin cifrar
  final String publicLine; // "ssh-ed25519 AAAA… comentario"
  GeneratedKey(this.privatePem, this.publicLine);
}

/// Genera pares ed25519 y los codifica en el formato OPENSSH PRIVATE KEY
/// (openssh-key-v1, cifrado "none") que dartssh2 sabe leer.
class KeygenService {
  static Future<GeneratedKey> generateEd25519(String comment) async {
    final algo = Ed25519();
    final pair = await algo.newKeyPair();
    final seed = Uint8List.fromList(await pair.extractPrivateKeyBytes());
    final pub = Uint8List.fromList((await pair.extractPublicKey()).bytes);

    final pubBlob = _blob([_str(ascii.encode('ssh-ed25519')), _str(pub)]);

    final check = Random.secure().nextInt(0xFFFFFFFF);
    final privateSection = BytesBuilder()
      ..add(_u32(check))
      ..add(_u32(check))
      ..add(_str(ascii.encode('ssh-ed25519')))
      ..add(_str(pub))
      ..add(_str(Uint8List.fromList([...seed, ...pub]))) // 64 bytes
      ..add(_str(utf8.encode(comment)));
    // Relleno 1,2,3… hasta múltiplo del bloque (8 con cifrado "none")
    var pad = 1;
    while (privateSection.length % 8 != 0) {
      privateSection.addByte(pad++);
    }

    final body = BytesBuilder()
      ..add(ascii.encode('openssh-key-v1'))
      ..addByte(0)
      ..add(_str(ascii.encode('none'))) // cipher
      ..add(_str(ascii.encode('none'))) // kdf
      ..add(_str(Uint8List(0))) // kdfoptions
      ..add(_u32(1)) // nº de claves
      ..add(_str(pubBlob))
      ..add(_str(privateSection.takeBytes()));

    final b64 = base64Encode(body.takeBytes());
    final lines = <String>[];
    for (var i = 0; i < b64.length; i += 70) {
      lines.add(b64.substring(i, min(i + 70, b64.length)));
    }
    final pem = '-----BEGIN OPENSSH PRIVATE KEY-----\n'
        '${lines.join('\n')}\n'
        '-----END OPENSSH PRIVATE KEY-----\n';
    final pubLine = 'ssh-ed25519 ${base64Encode(pubBlob)} $comment';
    return GeneratedKey(pem, pubLine);
  }

  static Uint8List _u32(int v) => Uint8List(4)
    ..buffer.asByteData().setUint32(0, v);

  static Uint8List _str(List<int> data) =>
      Uint8List.fromList([..._u32(data.length), ...data]);

  static Uint8List _blob(List<Uint8List> parts) =>
      Uint8List.fromList(parts.expand((p) => p).toList());
}
