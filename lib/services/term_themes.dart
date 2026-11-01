import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:xterm/xterm.dart';

import 'storage_service.dart';

/// Temas de color del terminal, seleccionables en Settings.
class TermThemes {
  static final ValueNotifier<String> notifier = ValueNotifier('Termius');

  static TerminalTheme get current =>
      themes[notifier.value] ?? themes['Termius']!;

  static Future<void> load() async {
    final saved = await StorageService.getTermTheme();
    if (saved != null && themes.containsKey(saved)) notifier.value = saved;
  }

  static Future<void> set(String name) async {
    if (!themes.containsKey(name)) return;
    notifier.value = name;
    await StorageService.saveTermTheme(name);
  }

  static final Map<String, TerminalTheme> themes = {
    'Termius': const TerminalTheme(
      cursor:       Color(0xFF4ECDC4),
      selection:    Color(0x504ECDC4),
      foreground:   Color(0xFFCDD6F4),
      background:   Color(0xFF0A0E1A),
      black:        Color(0xFF1E2740),
      red:          Color(0xFFFF6B6B),
      green:        Color(0xFF4ECDC4),
      yellow:       Color(0xFFFFD93D),
      blue:         Color(0xFF5B8AF5),
      magenta:      Color(0xFFC77DFF),
      cyan:         Color(0xFF4FC3F7),
      white:        Color(0xFFCDD6F4),
      brightBlack:  Color(0xFF45506A),
      brightRed:    Color(0xFFFF8E8E),
      brightGreen:  Color(0xFF6BDED8),
      brightYellow: Color(0xFFFFE566),
      brightBlue:   Color(0xFF7BA4FF),
      brightMagenta:Color(0xFFD89FFF),
      brightCyan:   Color(0xFF72D4F9),
      brightWhite:  Color(0xFFE8EAF0),
      searchHitBackground:        Color(0x804ECDC4),
      searchHitBackgroundCurrent: Color(0xFF4ECDC4),
      searchHitForeground:        Color(0xFF0A0E1A),
    ),
    'Dracula': const TerminalTheme(
      cursor:       Color(0xFFF8F8F2),
      selection:    Color(0x6044475A),
      foreground:   Color(0xFFF8F8F2),
      background:   Color(0xFF282A36),
      black:        Color(0xFF21222C),
      red:          Color(0xFFFF5555),
      green:        Color(0xFF50FA7B),
      yellow:       Color(0xFFF1FA8C),
      blue:         Color(0xFFBD93F9),
      magenta:      Color(0xFFFF79C6),
      cyan:         Color(0xFF8BE9FD),
      white:        Color(0xFFF8F8F2),
      brightBlack:  Color(0xFF6272A4),
      brightRed:    Color(0xFFFF6E6E),
      brightGreen:  Color(0xFF69FF94),
      brightYellow: Color(0xFFFFFFA5),
      brightBlue:   Color(0xFFD6ACFF),
      brightMagenta:Color(0xFFFF92DF),
      brightCyan:   Color(0xFFA4FFFF),
      brightWhite:  Color(0xFFFFFFFF),
      searchHitBackground:        Color(0x80BD93F9),
      searchHitBackgroundCurrent: Color(0xFFBD93F9),
      searchHitForeground:        Color(0xFF282A36),
    ),
    'Nord': const TerminalTheme(
      cursor:       Color(0xFFD8DEE9),
      selection:    Color(0x60434C5E),
      foreground:   Color(0xFFD8DEE9),
      background:   Color(0xFF2E3440),
      black:        Color(0xFF3B4252),
      red:          Color(0xFFBF616A),
      green:        Color(0xFFA3BE8C),
      yellow:       Color(0xFFEBCB8B),
      blue:         Color(0xFF81A1C1),
      magenta:      Color(0xFFB48EAD),
      cyan:         Color(0xFF88C0D0),
      white:        Color(0xFFE5E9F0),
      brightBlack:  Color(0xFF4C566A),
      brightRed:    Color(0xFFBF616A),
      brightGreen:  Color(0xFFA3BE8C),
      brightYellow: Color(0xFFEBCB8B),
      brightBlue:   Color(0xFF81A1C1),
      brightMagenta:Color(0xFFB48EAD),
      brightCyan:   Color(0xFF8FBCBB),
      brightWhite:  Color(0xFFECEFF4),
      searchHitBackground:        Color(0x8088C0D0),
      searchHitBackgroundCurrent: Color(0xFF88C0D0),
      searchHitForeground:        Color(0xFF2E3440),
    ),
    'Solarized Dark': const TerminalTheme(
      cursor:       Color(0xFF839496),
      selection:    Color(0x60073642),
      foreground:   Color(0xFF839496),
      background:   Color(0xFF002B36),
      black:        Color(0xFF073642),
      red:          Color(0xFFDC322F),
      green:        Color(0xFF859900),
      yellow:       Color(0xFFB58900),
      blue:         Color(0xFF268BD2),
      magenta:      Color(0xFFD33682),
      cyan:         Color(0xFF2AA198),
      white:        Color(0xFFEEE8D5),
      brightBlack:  Color(0xFF586E75),
      brightRed:    Color(0xFFCB4B16),
      brightGreen:  Color(0xFF586E75),
      brightYellow: Color(0xFF657B83),
      brightBlue:   Color(0xFF839496),
      brightMagenta:Color(0xFF6C71C4),
      brightCyan:   Color(0xFF93A1A1),
      brightWhite:  Color(0xFFFDF6E3),
      searchHitBackground:        Color(0x80268BD2),
      searchHitBackgroundCurrent: Color(0xFF268BD2),
      searchHitForeground:        Color(0xFF002B36),
    ),
    'Gruvbox Dark': const TerminalTheme(
      cursor:       Color(0xFFEBDBB2),
      selection:    Color(0x60504945),
      foreground:   Color(0xFFEBDBB2),
      background:   Color(0xFF282828),
      black:        Color(0xFF282828),
      red:          Color(0xFFCC241D),
      green:        Color(0xFF98971A),
      yellow:       Color(0xFFD79921),
      blue:         Color(0xFF458588),
      magenta:      Color(0xFFB16286),
      cyan:         Color(0xFF689D6A),
      white:        Color(0xFFA89984),
      brightBlack:  Color(0xFF928374),
      brightRed:    Color(0xFFFB4934),
      brightGreen:  Color(0xFFB8BB26),
      brightYellow: Color(0xFFFABD2F),
      brightBlue:   Color(0xFF83A598),
      brightMagenta:Color(0xFFD3869B),
      brightCyan:   Color(0xFF8EC07C),
      brightWhite:  Color(0xFFEBDBB2),
      searchHitBackground:        Color(0x80D79921),
      searchHitBackgroundCurrent: Color(0xFFD79921),
      searchHitForeground:        Color(0xFF282828),
    ),
  };
}
