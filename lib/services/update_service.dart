import 'dart:convert';
import 'dart:io';

import '../app_version.dart';

/// Comprobador de actualizaciones. SOLO se ejecuta cuando el usuario toca
/// «Buscar actualización» en Ajustes: una petición a la API pública de
/// GitHub y nada más (la app no hace ningún otro tráfico propio).
class UpdateInfo {
  final String version; // «6.16.0»
  final String url; // página de la release
  final bool isNewer;
  UpdateInfo(this.version, this.url, this.isNewer);
}

class UpdateService {
  static Future<UpdateInfo?> check() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(
          'https://api.github.com/repos/$kRepoOwner/$kRepoName/releases/latest'));
      req.headers.set('User-Agent', 'homelab-ssh/$kAppVersion');
      req.headers.set('Accept', 'application/vnd.github+json');
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final tag = (json['tag_name'] as String?) ?? '';
      final url = (json['html_url'] as String?) ??
          'https://github.com/$kRepoOwner/$kRepoName/releases';
      final latest = tag.startsWith('v') ? tag.substring(1) : tag;
      if (latest.isEmpty) return null;
      return UpdateInfo(latest, url, isNewer(latest, kAppVersion));
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// true si [a] es más nueva que [b] (comparación numérica por tramos)
  static bool isNewer(String a, String b) {
    final pa = a.split('.').map((x) => int.tryParse(x) ?? 0).toList();
    final pb = b.split('.').map((x) => int.tryParse(x) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va > vb;
    }
    return false;
  }
}
