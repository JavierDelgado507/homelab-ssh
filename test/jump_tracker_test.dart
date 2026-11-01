import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_ssh/services/jump_tracker.dart';

void main() {
  test('ssh interactivo apila', () {
    final ev = parseJumpCommand('ssh dagavi@192.168.1.174')!;
    expect(ev.pop, isFalse);
    expect(ev.push!.user, 'dagavi');
    expect(ev.push!.host, '192.168.1.174');
    expect(ev.push!.port, 22);
  });

  test('ssh con -p y -l', () {
    final ev = parseJumpCommand('ssh -p 2222 -l admin servidor')!;
    expect(ev.push!.user, 'admin');
    expect(ev.push!.port, 2222);
    expect(ev.push!.host, 'servidor');
  });

  test('flags con valor no se confunden con el destino', () {
    final ev = parseJumpCommand('ssh -i /root/.ssh/clave root@host')!;
    expect(ev.push!.host, 'host');
  });

  test('ssh con comando (one-shot) no cambia de sitio', () {
    expect(parseJumpCommand('ssh host uptime'), isNull);
  });

  test('pct enter apila un LXC', () {
    final ev = parseJumpCommand('pct enter 110')!;
    expect(ev.push!.isLxc, isTrue);
    expect(ev.push!.lxcId, 110);
  });

  test('pct exec con shell interactiva apila', () {
    final ev = parseJumpCommand('pct exec 105 -- bash')!;
    expect(ev.push!.lxcId, 105);
  });

  test('pct exec con comando normal no apila', () {
    expect(parseJumpCommand('pct exec 110 -- uptime'), isNull);
  });

  test('exit y logout desapilan', () {
    expect(parseJumpCommand('exit')!.pop, isTrue);
    expect(parseJumpCommand('logout')!.pop, isTrue);
  });

  test('comandos normales no hacen nada', () {
    expect(parseJumpCommand('ls -la'), isNull);
    expect(parseJumpCommand('htop'), isNull);
  });
}
