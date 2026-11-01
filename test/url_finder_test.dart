import 'package:flutter_test/flutter_test.dart';
import 'package:homelab_ssh/services/url_finder.dart';

void main() {
  test('encuentra la URL que pasa por la columna', () {
    const line = 'mira https://dagavi.es/manga y dime';
    expect(urlAt(line, 10), 'https://dagavi.es/manga');
    expect(urlAt(line, 5), 'https://dagavi.es/manga');
  });

  test('fuera de la URL no devuelve nada', () {
    const line = 'mira https://dagavi.es y dime';
    expect(urlAt(line, 0), isNull);
    expect(urlAt(line, line.length - 1), isNull);
  });

  test('recorta puntuación final', () {
    expect(urlAt('ver (https://github.com/x/y).', 10),
        'https://github.com/x/y');
    expect(urlAt('link: https://a.b/c,', 12), 'https://a.b/c');
  });

  test('varias URLs en la línea', () {
    const line = 'https://uno.es y https://dos.es';
    expect(urlAt(line, 2), 'https://uno.es');
    expect(urlAt(line, 20), 'https://dos.es');
  });

  test('http sin s también vale', () {
    expect(urlAt('http://192.168.1.150:8070 panel', 5),
        'http://192.168.1.150:8070');
  });
}
