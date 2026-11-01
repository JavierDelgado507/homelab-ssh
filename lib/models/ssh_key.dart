import 'package:uuid/uuid.dart';

const _uuid = Uuid();

class SshKey {
  final String id;
  String name;
  String? publicKey; // línea "ssh-ed25519 AAAA… comentario" (solo claves generadas)

  SshKey({String? id, required this.name, this.publicKey})
      : id = id ?? _uuid.v4();

  factory SshKey.fromJson(Map<String, dynamic> j) => SshKey(
        id: j['id'] as String,
        name: j['name'] as String,
        publicKey: j['publicKey'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (publicKey != null) 'publicKey': publicKey,
      };
}
