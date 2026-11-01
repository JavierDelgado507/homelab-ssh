final _urlRe = RegExp(r'https?://[^\s' r"'" r'"<>\[\]{}|\\^`]+');

/// Devuelve la URL que pasa por la columna [col] de [line], con la
/// puntuación final típica recortada; null si ahí no hay enlace.
String? urlAt(String line, int col) {
  for (final m in _urlRe.allMatches(line)) {
    if (col < m.start || col >= m.end) continue;
    var url = m.group(0)!;
    while (url.isNotEmpty && '.,;:)]'.contains(url[url.length - 1])) {
      url = url.substring(0, url.length - 1);
    }
    return url.isEmpty ? null : url;
  }
  return null;
}
