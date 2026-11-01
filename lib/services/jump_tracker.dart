/// Rastreo de los saltos hechos a mano dentro de un terminal: `ssh …`,
/// `pct enter <id>` / `pct exec <id> -- bash`, y `exit`/`logout` para
/// deshacerlos. El botón SFTP usa la pila para ofrecer «donde estás».

class RemoteLoc {
  final String user;
  final String host; // vacío en un LXC hasta resolver su IP
  final int port;
  final int? lxcId;
  RemoteLoc.ssh(this.user, this.host, this.port) : lxcId = null;
  RemoteLoc.lxc(this.lxcId)
      : user = 'root',
        host = '',
        port = 22;
  bool get isLxc => lxcId != null;
  String get label => isLxc ? 'LXC $lxcId' : '$user@$host:$port';
}

class JumpEvent {
  final RemoteLoc? push;
  final bool pop;
  const JumpEvent.enter(this.push) : pop = false;
  const JumpEvent.exit()
      : push = null,
        pop = true;
}

// Flags de ssh que llevan valor detrás (para no confundirlo con el destino)
const _sshValueFlags = {
  '-i', '-o', '-L', '-R', '-D', '-J', '-F', '-E', '-b', '-c', '-m', '-W'
};

/// Analiza un comando ejecutado y dice si entra a otro sitio, sale, o nada.
JumpEvent? parseJumpCommand(String cmd) {
  final parts = cmd.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return null;
  if (parts[0] == 'exit' || parts[0] == 'logout') {
    return const JumpEvent.exit();
  }
  if (parts[0] == 'pct') {
    int? id;
    if (parts.length == 3 && parts[1] == 'enter') {
      id = int.tryParse(parts[2]);
    } else if (parts.length == 5 &&
        parts[1] == 'exec' &&
        parts[3] == '--' &&
        const {'bash', 'sh', 'zsh', 'ash'}.contains(parts[4])) {
      id = int.tryParse(parts[2]);
    }
    return id == null ? null : JumpEvent.enter(RemoteLoc.lxc(id));
  }
  if (parts[0] != 'ssh') return null;
  String? target;
  String? userFlag;
  var port = 22;
  var i = 1;
  while (i < parts.length) {
    final p = parts[i];
    if (p == '-p' && i + 1 < parts.length) {
      port = int.tryParse(parts[i + 1]) ?? 22;
      i += 2;
    } else if (p == '-l' && i + 1 < parts.length) {
      userFlag = parts[i + 1];
      i += 2;
    } else if (_sshValueFlags.contains(p) && i + 1 < parts.length) {
      i += 2;
    } else if (p.startsWith('-')) {
      i++;
    } else {
      target = p;
      i++;
      break;
    }
  }
  if (target == null) return null;
  if (i < parts.length) return null; // "ssh host comando" no cambia de sitio
  final m = RegExp(r'^(?:([\w.\-]+)@)?([\w.\-]+)$').firstMatch(target);
  if (m == null) return null;
  return JumpEvent.enter(RemoteLoc.ssh(
    m.group(1) ?? userFlag ?? 'root',
    m.group(2)!,
    port,
  ));
}
