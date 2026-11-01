import 'dart:ui';
import 'package:flutter/painting.dart';

import 'package:xterm/src/ui/palette_builder.dart';
import 'package:xterm/src/ui/paragraph_cache.dart';
import 'package:xterm/xterm.dart';

/// Encapsulates the logic for painting various terminal elements.
class TerminalPainter {
  TerminalPainter({
    required TerminalTheme theme,
    required TerminalStyle textStyle,
    required TextScaler textScaler,
  })  : _textStyle = textStyle,
        _theme = theme,
        _textScaler = textScaler;

  /// A lookup table from terminal colors to Flutter colors.
  late var _colorPalette = PaletteBuilder(_theme).build();

  /// Size of each character in the terminal.
  late var _cellSize = _measureCharSize();

  /// The cached for cells in the terminal. Should be cleared when the same
  /// cell no longer produces the same visual output. For example, when
  /// [_textStyle] is changed, or when the system font changes.
  final _paragraphCache = ParagraphCache(10240);

  TerminalStyle get textStyle => _textStyle;
  TerminalStyle _textStyle;
  set textStyle(TerminalStyle value) {
    if (value == _textStyle) return;
    _textStyle = value;
    _cellSize = _measureCharSize();
    _paragraphCache.clear();
    _runCache.clear();
  }

  TextScaler get textScaler => _textScaler;
  TextScaler _textScaler = TextScaler.linear(1.0);
  set textScaler(TextScaler value) {
    if (value == _textScaler) return;
    _textScaler = value;
    _cellSize = _measureCharSize();
    _paragraphCache.clear();
    _runCache.clear();
  }

  TerminalTheme get theme => _theme;
  TerminalTheme _theme;
  set theme(TerminalTheme value) {
    if (value == _theme) return;
    _theme = value;
    _colorPalette = PaletteBuilder(value).build();
    _paragraphCache.clear();
    _runCache.clear();
  }

  Size _measureCharSize() {
    const test = 'mmmmmmmmmm';

    final textStyle = _textStyle.toTextStyle();
    final builder = ParagraphBuilder(textStyle.getParagraphStyle());
    builder.pushStyle(
      textStyle.getTextStyle(textScaler: _textScaler),
    );
    builder.addText(test);

    final paragraph = builder.build();
    paragraph.layout(ParagraphConstraints(width: double.infinity));

    final result = Size(
      paragraph.maxIntrinsicWidth / test.length,
      paragraph.height,
    );

    paragraph.dispose();
    return result;
  }

  /// The size of each character in the terminal.
  Size get cellSize => _cellSize;

  /// When the set of font available to the system changes, call this method to
  /// clear cached state related to font rendering.
  void clearFontCache() {
    _cellSize = _measureCharSize();
    _paragraphCache.clear();
    _runCache.clear();
  }

  /// Paints the cursor based on the current cursor type.
  void paintCursor(
    Canvas canvas,
    Offset offset, {
    required TerminalCursorType cursorType,
    bool hasFocus = true,
  }) {
    final paint = Paint()
      ..color = _theme.cursor
      ..strokeWidth = 1;

    if (!hasFocus) {
      paint.style = PaintingStyle.stroke;
      canvas.drawRect(offset & _cellSize, paint);
      return;
    }

    switch (cursorType) {
      case TerminalCursorType.block:
        paint.style = PaintingStyle.fill;
        canvas.drawRect(offset & _cellSize, paint);
        return;
      case TerminalCursorType.underline:
        return canvas.drawLine(
          Offset(offset.dx, _cellSize.height - 1),
          Offset(offset.dx + _cellSize.width, _cellSize.height - 1),
          paint,
        );
      case TerminalCursorType.verticalBar:
        return canvas.drawLine(
          Offset(offset.dx, 0),
          Offset(offset.dx, _cellSize.height),
          paint,
        );
    }
  }

  @pragma('vm:prefer-inline')
  void paintHighlight(Canvas canvas, Offset offset, int length, Color color) {
    final endOffset =
        offset.translate(length * _cellSize.width, _cellSize.height);

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    canvas.drawRect(
      Rect.fromPoints(offset, endOffset),
      paint,
    );
  }

  // homelab-ssh: dibujado por tramos. El original hacía un drawParagraph y un
  // drawRect por celda (~3000 llamadas por frame); aquí los fondos de un mismo
  // color se unen en un rectángulo y el texto de un mismo estilo en un párrafo.
  final _cell = CellData.empty();
  final _bgPaint = Paint();
  final _runText = StringBuffer();
  final _runCache = _RunCache(2048);

  /// Paints [line] to [canvas] at [offset]. The x offset of [offset] is usually
  /// 0, and the y offset is the top of the line.
  void paintLine(
    Canvas canvas,
    Offset offset,
    BufferLine line, {
    bool volatileLine = false,
  }) {
    _paintLineBackground(canvas, offset, line);
    if (volatileLine) {
      // Línea del cursor: cambia con cada tecla. Por celdas (cada carácter ya
      // está en caché), sin maquetar la línea entera en cada pulsación.
      _paintLineCells(canvas, offset, line);
    } else {
      _paintLineForeground(canvas, offset, line);
    }
  }

  void _paintLineCells(Canvas canvas, Offset offset, BufferLine line) {
    final cell = _cell;
    final cw = _cellSize.width;
    for (var i = 0; i < line.length; i++) {
      line.getCellData(i, cell);
      final cp = cell.content & CellContent.codepointMask;
      if (cp != 0) {
        paintCellForeground(canvas, offset.translate(i * cw, 0), cell);
      }
      if (cell.content >> CellContent.widthShift == 2) i++;
    }
  }

  void _paintLineBackground(Canvas canvas, Offset offset, BufferLine line) {
    final cell = _cell;
    final cw = _cellSize.width;
    final len = line.length;
    Color? runColor;
    var runStart = 0;

    void flush(int end) {
      if (runColor == null) return;
      _bgPaint.color = runColor;
      canvas.drawRect(
        Rect.fromLTWH(offset.dx + runStart * cw, offset.dy,
            (end - runStart) * cw + 1, _cellSize.height),
        _bgPaint,
      );
    }

    for (var i = 0; i < len; i++) {
      line.getCellData(i, cell);
      Color? color;
      if (cell.flags & CellFlags.inverse != 0) {
        color = resolveForegroundColor(cell.foreground);
      } else if (cell.background & CellColor.typeMask != CellColor.normal) {
        color = resolveBackgroundColor(cell.background);
      }
      if (color != runColor) {
        flush(i);
        runColor = color;
        runStart = i;
      }
    }
    flush(len);
  }

  /// Caracteres que se pueden agrupar: anchura 1 y sin marcas combinantes.
  /// Si la fuente no los dibuja con el ancho de celda, la comprobación de
  /// ancho del tramo lo detecta y se pinta celda a celda.
  @pragma('vm:prefer-inline')
  static bool _groupable(int cp) =>
      cp >= 0x20 && cp < 0x3000 && !(cp >= 0x0300 && cp < 0x0370);

  void _paintLineForeground(Canvas canvas, Offset offset, BufferLine line) {
    final cell = _cell;
    final len = line.length;
    final cw = _cellSize.width;
    var runStart = -1;
    var runStyle = 0;
    var runFg = 0, runBg = 0, runFlags = 0;

    void flush() {
      if (runStart < 0) return;
      _drawRun(canvas, offset, line, runStart, runFg, runBg, runFlags,
          runStyle);
      runStart = -1;
      _runText.clear();
    }

    for (var i = 0; i < len; i++) {
      line.getCellData(i, cell);
      final cp = cell.content & CellContent.codepointMask;
      final width = cell.content >> CellContent.widthShift;

      if (cp == 0 || width != 1 || !_groupable(cp)) {
        flush();
        if (cp != 0) {
          paintCellForeground(canvas, offset.translate(i * cw, 0), cell);
        }
        if (width == 2) i++;
        continue;
      }

      final style = Object.hash(cell.foreground,
          cell.flags & CellFlags.inverse != 0 ? cell.background : 0,
          cell.flags);
      if (runStart >= 0 && style != runStyle) flush();
      if (runStart < 0) {
        runStart = i;
        runStyle = style;
        runFg = cell.foreground;
        runBg = cell.background;
        runFlags = cell.flags;
      }
      _runText.writeCharCode(
          cp == 0x20 && cell.flags & CellFlags.underline != 0 ? 0xA0 : cp);
    }
    flush();
  }

  void _drawRun(Canvas canvas, Offset offset, BufferLine line, int start,
      int fg, int bg, int flags, int style) {
    var text = _runText.toString();
    var col = start;
    // Los espacios sin subrayado no pintan nada: se recortan.
    if (flags & CellFlags.underline == 0) {
      final trimmedLeft = text.trimLeft();
      col += text.length - trimmedLeft.length;
      text = trimmedLeft.trimRight();
      if (text.isEmpty) return;
    }

    final key = '$style:${_textScaler.hashCode}:$text';
    var run = _runCache[key];
    if (run == null && !_runCache.shouldBuild(key)) {
      // Texto recién aparecido (p. ej. se está escribiendo o borrando): puede
      // no repetirse, así que se pinta por celdas, que ya están en caché.
      // Solo si reaparece en otro frame se maqueta el tramo entero.
      return _paintRunCells(canvas, offset, line, col, text.length);
    }
    if (run == null) {
      var color = flags & CellFlags.inverse == 0
          ? resolveForegroundColor(fg)
          : resolveBackgroundColor(bg);
      if (flags & CellFlags.faint != 0) color = color.withOpacity(0.5);
      final textStyle = _textStyle.toTextStyle(
        color: color,
        bold: flags & CellFlags.bold != 0,
        italic: flags & CellFlags.italic != 0,
        underline: flags & CellFlags.underline != 0,
      );
      final builder = ParagraphBuilder(textStyle.getParagraphStyle())
        ..pushStyle(textStyle.getTextStyle(textScaler: _textScaler))
        ..addText(text);
      final paragraph = builder.build()
        ..layout(const ParagraphConstraints(width: double.infinity));
      final expected = text.length * _cellSize.width;
      final aligned = (paragraph.maxIntrinsicWidth - expected).abs() < 0.5;
      run = _Run(aligned ? paragraph : null);
      if (!aligned) paragraph.dispose();
      _runCache[key] = run;
    }

    final p = run.paragraph;
    if (p != null) {
      canvas.drawParagraph(p, offset.translate(col * _cellSize.width, 0));
      return;
    }
    // Tramo que no cuadra con la rejilla (otra fuente): celda a celda.
    _paintRunCells(canvas, offset, line, col, text.length);
  }

  void _paintRunCells(
      Canvas canvas, Offset offset, BufferLine line, int col, int len) {
    final cell = CellData.empty();
    for (var i = col; i < col + len; i++) {
      line.getCellData(i, cell);
      paintCellForeground(
          canvas, offset.translate(i * _cellSize.width, 0), cell);
    }
  }

  @pragma('vm:prefer-inline')
  void paintCell(Canvas canvas, Offset offset, CellData cellData) {
    paintCellBackground(canvas, offset, cellData);
    paintCellForeground(canvas, offset, cellData);
  }

  /// Paints the character in the cell represented by [cellData] to [canvas] at
  /// [offset].
  @pragma('vm:prefer-inline')
  void paintCellForeground(Canvas canvas, Offset offset, CellData cellData) {
    final charCode = cellData.content & CellContent.codepointMask;
    if (charCode == 0) return;

    final cacheKey = cellData.getHash() ^ _textScaler.hashCode;
    var paragraph = _paragraphCache.getLayoutFromCache(cacheKey);

    if (paragraph == null) {
      final cellFlags = cellData.flags;

      var color = cellFlags & CellFlags.inverse == 0
          ? resolveForegroundColor(cellData.foreground)
          : resolveBackgroundColor(cellData.background);

      if (cellData.flags & CellFlags.faint != 0) {
        color = color.withOpacity(0.5);
      }

      final style = _textStyle.toTextStyle(
        color: color,
        bold: cellFlags & CellFlags.bold != 0,
        italic: cellFlags & CellFlags.italic != 0,
        underline: cellFlags & CellFlags.underline != 0,
      );

      // Flutter does not draw an underline below a space which is not between
      // other regular characters. As only single characters are drawn, this
      // will never produce an underline below a space in the terminal. As a
      // workaround the regular space CodePoint 0x20 is replaced with
      // the CodePoint 0xA0. This is a non breaking space and a underline can be
      // drawn below it.
      var char = String.fromCharCode(charCode);
      if (cellFlags & CellFlags.underline != 0 && charCode == 0x20) {
        char = String.fromCharCode(0xA0);
      }

      paragraph = _paragraphCache.performAndCacheLayout(
        char,
        style,
        _textScaler,
        cacheKey,
      );
    }

    canvas.drawParagraph(paragraph, offset);
  }

  /// Paints the background of a cell represented by [cellData] to [canvas] at
  /// [offset].
  @pragma('vm:prefer-inline')
  void paintCellBackground(Canvas canvas, Offset offset, CellData cellData) {
    late Color color;
    final colorType = cellData.background & CellColor.typeMask;

    if (cellData.flags & CellFlags.inverse != 0) {
      color = resolveForegroundColor(cellData.foreground);
    } else if (colorType == CellColor.normal) {
      return;
    } else {
      color = resolveBackgroundColor(cellData.background);
    }

    final paint = Paint()..color = color;
    final doubleWidth = cellData.content >> CellContent.widthShift == 2;
    final widthScale = doubleWidth ? 2 : 1;
    final size = Size(_cellSize.width * widthScale + 1, _cellSize.height);
    canvas.drawRect(offset & size, paint);
  }

  /// Get the effective foreground color for a cell from information encoded in
  /// [cellColor].
  @pragma('vm:prefer-inline')
  Color resolveForegroundColor(int cellColor) {
    final colorType = cellColor & CellColor.typeMask;
    final colorValue = cellColor & CellColor.valueMask;

    switch (colorType) {
      case CellColor.normal:
        return _theme.foreground;
      case CellColor.named:
      case CellColor.palette:
        return _colorPalette[colorValue];
      case CellColor.rgb:
      default:
        return Color(colorValue | 0xFF000000);
    }
  }

  /// Get the effective background color for a cell from information encoded in
  /// [cellColor].
  @pragma('vm:prefer-inline')
  Color resolveBackgroundColor(int cellColor) {
    final colorType = cellColor & CellColor.typeMask;
    final colorValue = cellColor & CellColor.valueMask;

    switch (colorType) {
      case CellColor.normal:
        return _theme.background;
      case CellColor.named:
      case CellColor.palette:
        return _colorPalette[colorValue];
      case CellColor.rgb:
      default:
        return Color(colorValue | 0xFF000000);
    }
  }
}

class _Run {
  _Run(this.paragraph);

  /// null si el tramo no cuadra con la rejilla y hay que pintarlo por celdas.
  final Paragraph? paragraph;
}

/// LRU sencilla de tramos ya maquetados.
class _RunCache {
  _RunCache(this.maxSize);

  final int maxSize;
  final _map = <String, _Run>{};

  _Run? operator [](String key) {
    final run = _map.remove(key);
    if (run != null) _map[key] = run;
    return run;
  }

  void operator []=(String key, _Run run) {
    _map.remove(key)?.paragraph?.dispose();
    _map[key] = run;
    if (_map.length > maxSize) {
      // Liberar la parte nativa del párrafo: si no, escribir/borrar rápido
      // acumula párrafos huérfanos y la app se degrada con el uso.
      _map.remove(_map.keys.first)?.paragraph?.dispose();
    }
  }

  /// true si esta clave ya se vio antes (merece maquetarse entera);
  /// si es la primera vez, la apunta y devuelve false.
  bool shouldBuild(String key) {
    if (_seen.remove(key)) {
      _seen.add(key);
      return true;
    }
    _seen.add(key);
    if (_seen.length > maxSize) _seen.remove(_seen.first);
    return false;
  }

  final _seen = <String>{};

  void clear() {
    for (final run in _map.values) {
      run.paragraph?.dispose();
    }
    _map.clear();
    _seen.clear();
  }
}
