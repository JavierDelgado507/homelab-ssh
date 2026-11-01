import 'dart:io';

import 'package:flutter/foundation.dart';

import 'storage_service.dart';

/// Idioma de la interfaz. Las cadenas del código están en inglés; `tr()`
/// las traduce al español cuando toca. Por defecto, el idioma del sistema.
class Tr {
  static final ValueNotifier<String> notifier = ValueNotifier('en');
  static bool get es => notifier.value == 'es';
  static String get lang => notifier.value;

  static Future<void> load() async {
    final saved = await StorageService.getLang();
    if (saved == 'en' || saved == 'es') {
      notifier.value = saved!;
    } else {
      notifier.value =
          Platform.localeName.toLowerCase().startsWith('es') ? 'es' : 'en';
    }
  }

  static Future<void> set(String l) async {
    notifier.value = l;
    await StorageService.setLang(l);
  }
}

String tr(String en) => Tr.es ? (_es[en] ?? en) : en;

const _es = <String, String>{
  // Común
  'Cancel': 'Cancelar',
  'OK': 'Aceptar',
  'Save': 'Guardar',
  'Delete': 'Eliminar',
  'Edit': 'Editar',
  'Connect': 'Conectar',
  'Close': 'Cerrar',
  'Copy': 'Copiar',
  'Retry': 'Reintentar',
  'Password': 'Contraseña',
  'Name': 'Nombre',
  'Rename': 'Renombrar',
  // Navegación
  'Keys': 'Claves',
  'Settings': 'Ajustes',
  // Hosts
  'Delete host': 'Eliminar host',
  'Quick connect': 'Conexión rápida',
  'Connect via SFTP': 'Conectar por SFTP',
  'Address': 'Dirección',
  'Save to hosts': 'Guardar en hosts',
  'Invalid address': 'Dirección no válida',
  'Ways to connect': 'Formas de conectar',
  'Local terminal': 'Terminal local',
  'A shell on this device': 'Una shell del propio móvil',
  'Add host': 'Añadir host',
  'Save a new server': 'Dar de alta un servidor',
  'Browse files without opening a terminal':
      'Explorar ficheros sin abrir terminal',
  'Discover local devices': 'Descubrir en la red',
  'Scan your LAN for SSH servers': 'Buscar dispositivos con SSH en la LAN',
  'Search, or "ssh root@ip -p 22"…': 'Buscar, o "ssh root@ip -p 22"…',
  'All': 'Todos',
  'Duplicate': 'Duplicar',
  'No hosts yet': 'Sin hosts guardados',
  'Tap + to add your first host': 'Pulsa + para añadir tu primer host',
  'New terminal': 'Nueva terminal',
  // Alta de host
  'Could not read the SSH key': 'La clave SSH no se pudo leer',
  'No response (connection timed out)': 'No responde (tiempo agotado)',
  'Select an SSH key': 'Selecciona una clave SSH',
  'Could not connect': 'No se pudo conectar',
  'Save anyway': 'Guardar igualmente',
  'Fix it': 'Corregir',
  'New host': 'Nuevo host',
  'Edit host': 'Editar host',
  'My Proxmox server': 'Mi servidor Proxmox',
  'Group (optional)': 'Grupo (opcional)',
  'General': 'General',
  'Connection': 'Conexión',
  'Port': 'Puerto',
  'Invalid port (1-65535)': 'Puerto inválido (1-65535)',
  'User': 'Usuario',
  'Connect through (ProxyJump)': 'Conectar a través de (ProxyJump)',
  'Direct': 'Directo',
  'Authentication': 'Autenticación',
  'SSH key': 'Clave SSH',
  'No keys yet. Add one in the Keys tab.':
      'Sin claves guardadas. Añade una en la pestaña Claves.',
  'On connect': 'Al conectar',
  'Startup command (optional)': 'Comando de arranque (opcional)',
  'Persistent session (tmux)': 'Sesión persistente (tmux)',
  'Reconnect right where you left off. Requires tmux on the server; the startup command runs inside it (only when the session is created).':
      'Al reconectar vuelves donde estabas. Requiere tmux en el servidor; el comando de arranque se ejecuta dentro (solo al crear la sesión).',
  'Required': 'Obligatorio',
  // Claves
  'The file does not look like a PEM private key':
      'El fichero no parece una clave privada PEM',
  'Paste private key': 'Pegar clave privada',
  'PEM key': 'Clave PEM',
  'Wrong passphrase: the key cannot be decrypted':
      'Passphrase incorrecta: la clave no se descifra',
  'Protected key': 'Clave protegida',
  'Generate ed25519 key': 'Generar clave ed25519',
  'Name (also used as comment)': 'Nombre (también va de comentario)',
  'Generate': 'Generar',
  'Copied. Paste it into ~/.ssh/authorized_keys on the server':
      'Copiada. Pégala en ~/.ssh/authorized_keys del servidor',
  'Delete key': 'Eliminar clave',
  'SSH keys': 'Claves SSH',
  'Paste key': 'Pegar clave',
  'Import file': 'Importar fichero',
  'No keys yet': 'Sin claves guardadas',
  'Use the icons above to import or generate':
      'Usa los iconos de arriba para importar o generar',
  'ed25519 generated in-app': 'ed25519 generada en la app',
  'Private key': 'Clave privada',
  'Show public key': 'Ver clave pública',
  // Snippets
  'New snippet': 'Nuevo snippet',
  'Edit snippet': 'Editar snippet',
  'Command': 'Comando',
  'No snippets. Tap + to add one.': 'Sin snippets. Pulsa + para añadir.',
  'Processes': 'Procesos',
  'Disk usage': 'Uso de disco',
  'Memory': 'Memoria',
  'System log': 'Log del sistema',
  'Upgrade': 'Actualizar',
  // SFTP
  'New folder': 'Nueva carpeta',
  'Create': 'Crear',
  'Delete folder': 'Eliminar carpeta',
  'Delete file': 'Eliminar fichero',
  'Download': 'Descargar',
  'Upload file': 'Subir fichero',
  'Download cancelled': 'Descarga cancelada',
  'Export cancelled': 'Exportación cancelada',
  // Huellas
  'Forget fingerprint': 'Olvidar huella',
  'Forget': 'Olvidar',
  'Server fingerprints': 'Huellas de servidores',
  'No fingerprints yet': 'Sin huellas guardadas',
  'They are recorded the first time you connect':
      'Se registran solas la primera vez que conectas',
  // Descubrir
  'Could not determine the local network (no Wi-Fi?)':
      'No se pudo averiguar la red local (¿sin wifi?)',
  'Nothing with SSH in sight': 'Nada con SSH a la vista',
  // Terminal
  'Connecting…': 'Conectando…',
  'Disconnected': 'Desconectado',
  'Network error': 'Error de red',
  'Session lost': 'Sesión perdida',
  'Authentication failed': 'Fallo de autenticación',
  'Starting…': 'Iniciando…',
  'Ended': 'Terminado',
  'Reconnect': 'Reconectar',
  'Open SFTP of…': 'Abrir SFTP de…',
  'Where you are now (ssh jump)': 'Donde estás ahora (salto ssh)',
  'Where you are now (pct — IP will be resolved)':
      'Donde estás ahora (pct — se resolverá su IP)',
  'The original connection of this tab': 'La conexión original de esta pestaña',
  'Home (sessions stay alive)': 'Menú principal (las sesiones siguen vivas)',
  // Servicio SSH
  '⚠ Server fingerprint has changed': '⚠ La huella del servidor ha cambiado',
  'Trust and update': 'Confiar y actualizar',
  'SSH key not found': 'Clave SSH no encontrada',
  // Ajustes
  'Biometric lock': 'Bloqueo biométrico',
  'Ask for fingerprint or PIN when opening the app':
      'Pide huella o PIN al abrir la app',
  'Confirm your identity to enable the lock':
      'Confirma tu identidad para activar el bloqueo',
  'This device has no fingerprint or PIN configured':
      'Este dispositivo no tiene huella ni PIN configurados',
  'Export backup': 'Exportar copia',
  'Hosts, keys, passwords and snippets in an encrypted file':
      'Hosts, claves, contraseñas y snippets en un fichero cifrado',
  'Import backup': 'Importar copia',
  'Restore an encrypted .hssh backup': 'Restaurar una copia .hssh cifrada',
  'Encrypt the backup': 'Cifrar la copia',
  'Backup password': 'Contraseña de la copia',
  'Repeat': 'Repetir',
  'Passwords do not match': 'Las contraseñas no coinciden',
  'Backup saved (hosts, keys, passwords and snippets)':
      'Copia guardada (hosts, claves, contraseñas y snippets)',
  'Wrong password or corrupted backup':
      'Contraseña incorrecta o copia dañada',
  'Known host keys (trust on first use)':
      'Huellas conocidas (se fían del primer uso)',
  'About': 'Acerca de',
  'Language': 'Idioma',
  'Not a Homelab SSH backup': 'No es una copia de Homelab SSH',
  // Bloqueo
  'Homelab SSH is locked': 'Homelab SSH está bloqueada',
  'Unlock': 'Desbloquear',
  'Unlock Homelab SSH': 'Desbloquear Homelab SSH',
};
