import 'package:uuid/uuid.dart';

const _uuid = Uuid();

class Host {
  final String id;
  String name;
  String hostname;
  int port;
  String username;
  String authType; // 'password' | 'key'
  String? keyId;
  String startupCmd; // comando que se manda nada más abrir la shell ('' = nada)
  String? jumpHostId; // ProxyJump: id de otro host por el que saltar
  String group;       // etiqueta de grupo ('' = sin grupo)
  bool useTmux;       // sesión persistente: tmux new -A al conectar

  Host({
    String? id,
    required this.name,
    required this.hostname,
    this.port = 22,
    required this.username,
    this.authType = 'password',
    this.keyId,
    this.startupCmd = '',
    this.jumpHostId,
    this.group = '',
    this.useTmux = false,
  }) : id = id ?? _uuid.v4();

  factory Host.fromJson(Map<String, dynamic> j) => Host(
        id: j['id'] as String,
        name: j['name'] as String,
        hostname: j['hostname'] as String,
        port: (j['port'] as int?) ?? 22,
        username: j['username'] as String,
        authType: (j['authType'] as String?) ?? 'password',
        keyId: j['keyId'] as String?,
        startupCmd: (j['startupCmd'] as String?) ?? '',
        jumpHostId: j['jumpHostId'] as String?,
        group: (j['group'] as String?) ?? '',
        useTmux: (j['useTmux'] as bool?) ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'hostname': hostname,
        'port': port,
        'username': username,
        'authType': authType,
        if (keyId != null) 'keyId': keyId,
        if (startupCmd.isNotEmpty) 'startupCmd': startupCmd,
        if (jumpHostId != null) 'jumpHostId': jumpHostId,
        if (group.isNotEmpty) 'group': group,
        if (useTmux) 'useTmux': useTmux,
      };
}
