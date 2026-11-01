import 'dart:ui';

import 'package:flutter/widgets.dart';

/// A cache of laid out [Paragraph]s. This is used to avoid laying out the same
/// text multiple times, which is expensive.
///
/// homelab-ssh: reescrita sin LruMap para liberar (dispose) la parte nativa de
/// los párrafos expulsados; el original los dejaba huérfanos y la app se
/// degradaba con el uso.
class ParagraphCache {
  ParagraphCache(this.maximumSize);

  final int maximumSize;

  final _map = <int, Paragraph>{};

  /// Returns a [Paragraph] for the given [key]. [key] is the same as the
  /// key argument to [performAndCacheLayout].
  Paragraph? getLayoutFromCache(int key) {
    final paragraph = _map.remove(key);
    if (paragraph != null) _map[key] = paragraph;
    return paragraph;
  }

  /// Applies [style] and [textScaler] to [text] and lays it out to create
  /// a [Paragraph]. The [Paragraph] is cached and can be retrieved with the
  /// same [key] by calling [getLayoutFromCache].
  Paragraph performAndCacheLayout(
    String text,
    TextStyle style,
    TextScaler textScaler,
    int key,
  ) {
    final builder = ParagraphBuilder(style.getParagraphStyle());
    builder.pushStyle(style.getTextStyle(textScaler: textScaler));
    builder.addText(text);

    final paragraph = builder.build();
    paragraph.layout(ParagraphConstraints(width: double.infinity));

    _map.remove(key)?.dispose();
    _map[key] = paragraph;
    if (_map.length > maximumSize) {
      _map.remove(_map.keys.first)?.dispose();
    }
    return paragraph;
  }

  /// Clears the cache. This should be called when the same text and style
  /// pair no longer produces the same layout. For example, when a font is
  /// loaded.
  void clear() {
    for (final paragraph in _map.values) {
      paragraph.dispose();
    }
    _map.clear();
  }

  /// Returns the number of [Paragraph]s in the cache.
  int get length {
    return _map.length;
  }
}
