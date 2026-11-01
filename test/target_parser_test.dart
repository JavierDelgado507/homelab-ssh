import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_ssh/services/target_parser.dart';

void main() {
  test('usuario@host', () {
    final t = parseTarget('root@192.168.1.99')!;
    expect(t.user, 'root');
    expect(t.host, '192.168.1.99');
    expect(t.port, 22);
  });

  test('sintaxis ssh completa con -p', () {
    final t = parseTarget('ssh dagavi@mi-servidor.lan -p 2222')!;
    expect(t.user, 'dagavi');
    expect(t.host, 'mi-servidor.lan');
    expect(t.port, 2222);
  });

  test('host:puerto', () {
    final t = parseTarget('10.0.0.5:2200')!;
    expect(t.user, 'root');
    expect(t.port, 2200);
  });

  test('una palabra suelta es búsqueda, no dirección', () {
    expect(parseTarget('proxmox'), isNull);
  });

  test('palabra suelta con prefijo ssh sí es dirección', () {
    final t = parseTarget('ssh proxmox')!;
    expect(t.host, 'proxmox');
  });

  test('texto arbitrario no cuela', () {
    expect(parseTarget('hola que tal'), isNull);
    expect(parseTarget(''), isNull);
  });
}
