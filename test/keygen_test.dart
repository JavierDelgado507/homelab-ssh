import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_ssh/services/keygen_service.dart';

void main() {
  test('la clave generada la entiende dartssh2 y la pública es coherente',
      () async {
    final gen = await KeygenService.generateEd25519('test@homelab-ssh');

    expect(gen.privatePem, contains('BEGIN OPENSSH PRIVATE KEY'));
    final pairs = SSHKeyPair.fromPem(gen.privatePem);
    expect(pairs, hasLength(1));

    expect(gen.publicLine, startsWith('ssh-ed25519 '));
    expect(gen.publicLine, endsWith(' test@homelab-ssh'));
  });

  test('dos generaciones dan claves distintas', () async {
    final a = await KeygenService.generateEd25519('x');
    final b = await KeygenService.generateEd25519('x');
    expect(a.publicLine, isNot(equals(b.publicLine)));
  });
}
