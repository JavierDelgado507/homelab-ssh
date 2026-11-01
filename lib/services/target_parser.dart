/// Entiende "usuario@host:puerto", "ssh usuario@host -p puerto" o una IP.
/// Una palabra suelta sin puntos es una búsqueda normal, no una dirección
/// (salvo que venga con el prefijo "ssh " o un -p explícito).
({String user, String host, int port})? parseTarget(String input) {
  var s = input.trim();
  final hadSshPrefix = s.toLowerCase().startsWith('ssh ');
  if (hadSshPrefix) s = s.substring(4).trim();
  int? pFlag;
  final mp = RegExp(r'\s+-p\s*(\d{1,5})\s*$').firstMatch(s);
  if (mp != null) {
    pFlag = int.tryParse(mp.group(1)!);
    s = s.substring(0, mp.start).trim();
  }
  final m =
      RegExp(r'^(?:([\w.\-]+)@)?([\w.\-]+)(?::(\d{1,5}))?$').firstMatch(s);
  if (m == null) return null;
  final host = m.group(2)!;
  if (!hadSshPrefix &&
      pFlag == null &&
      m.group(1) == null &&
      m.group(3) == null &&
      !host.contains('.')) {
    return null;
  }
  return (
    user: m.group(1) ?? 'root',
    host: host,
    port: pFlag ?? int.tryParse(m.group(3) ?? '') ?? 22,
  );
}
