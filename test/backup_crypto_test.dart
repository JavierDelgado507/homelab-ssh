import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_ssh/services/backup_service.dart';

void main() {
  final datos = {
    'hosts': '[{"id":"1","name":"Proxmox"}]',
    'pw_1': 'supersecreta',
    'snippets': '[]',
  };

  test('cifrar y descifrar recupera el volcado exacto', () async {
    final blob = await BackupService.encryptPayload(datos, 'clave123');
    final back = await BackupService.decryptPayload(blob, 'clave123');
    expect(back, datos);
  });

  test('contraseña incorrecta no descifra', () async {
    final blob = await BackupService.encryptPayload(datos, 'clave123');
    expect(
      () => BackupService.decryptPayload(blob, 'otra'),
      throwsA(anything),
    );
  });

  test('un fichero que no es una copia se rechaza', () async {
    expect(
      () => BackupService.decryptPayload(
          Uint8List.fromList(List.filled(64, 7)), 'clave123'),
      throwsA(isA<FormatException>()),
    );
  });

  test('cada export usa sal y nonce distintos', () async {
    final a = await BackupService.encryptPayload(datos, 'clave123');
    final b = await BackupService.encryptPayload(datos, 'clave123');
    expect(a, isNot(equals(b)));
  });
}
