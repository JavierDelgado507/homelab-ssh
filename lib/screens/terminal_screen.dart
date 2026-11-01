import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xterm/xterm.dart';
import '../main.dart';
import '../models/host.dart';
import '../services/i18n.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/ssh_connect_service.dart';
import '../services/term_themes.dart';
import '../services/storage_service.dart';
import '../services/ssh_keepalive_service.dart';
import 'sftp_screen.dart';
import 'terminal_tabs_screen.dart' show TabsHub;
import 'snippets_screen.dart';

// ── Secuencias de escape ─────────────────────────────────────────────────────
const _kEsc    = '\x1b';
const _kTab    = '\t';
const _kEnter  = '\r';
const _kBs     = '\x7f';
const _kDel    = '\x1b[3~';
const _kIns    = '\x1b[2~';
const _kUp     = '\x1b[A';
const _kDown   = '\x1b[B';
const _kRight  = '\x1b[C';
const _kLeft   = '\x1b[D';
const _kPgUp   = '\x1b[5~';
const _kPgDown = '\x1b[6~';
const _kHome   = '\x1b[H';
const _kEnd    = '\x1b[F';
const _kShTab  = '\x1b[Z';
const _kF1  = '\x1bOP';  const _kF2  = '\x1bOQ';
const _kF3  = '\x1bOR';  const _kF4  = '\x1bOS';
const _kF5  = '\x1b[15~'; const _kF6 = '\x1b[17~';
const _kF7  = '\x1b[18~'; const _kF8 = '\x1b[19~';
const _kF9  = '\x1b[20~'; const _kF10= '\x1b[21~';
const _kF11 = '\x1b[23~'; const _kF12= '\x1b[24~';
// Teclas Fn en popup (F13-F20 eliminadas)


class _Key {
  final String label;
  final String seq;
  final IconData? icon;
  const _Key(this.label, this.seq, {this.icon});
}

const _rowNav = [
  _Key('ESC', _kEsc),  _Key('TAB', _kTab),  _Key('⇤', _kShTab),
  _Key('', _kUp,    icon: Icons.keyboard_arrow_up),
  _Key('', _kDown,  icon: Icons.keyboard_arrow_down),
  _Key('', _kLeft,  icon: Icons.keyboard_arrow_left),
  _Key('', _kRight, icon: Icons.keyboard_arrow_right),
  _Key('Home', _kHome), _Key('End', _kEnd),
  _Key('PgUp', _kPgUp), _Key('PgDn', _kPgDown),
  _Key('Ins', _kIns),   _Key('Del', _kDel),
  _Key('↵', _kEnter),   _Key('⌫', _kBs),
];

const _rowSym = [
  _Key('|','|'), _Key('~','~'), _Key('/','/' ), _Key(':',':'),
  _Key('-','-'), _Key('_','_'), _Key('&','&'), _Key('+','+'),
  _Key('=','='), _Key(';',';'),
  _Key(r'$',r'$'), _Key('%','%'), _Key('@','@'), _Key('#','#'),
  _Key('!','!'), _Key('`','`'), _Key('.','.'), _Key('*','*'),
  _Key('^','^'), _Key('<','<'), _Key('>','>'),
  _Key('(','('), _Key(')',')'), _Key('{','{'), _Key('}','}'),
  _Key('[','['), _Key(']',']'), _Key("'","'"),
  _Key('"','"'), _Key('\\','\\'), _Key('?','?'),
];

const _rowCtrl = [
  _Key('^A','\x01'), _Key('^B','\x02'), _Key('^C','\x03'),
  _Key('^D','\x04'), _Key('^E','\x05'), _Key('^F','\x06'),
  _Key('^G','\x07'), _Key('^H','\x08'), _Key('^I','\x09'),
  _Key('^J','\x0a'), _Key('^K','\x0b'), _Key('^L','\x0c'),
  _Key('^M','\x0d'), _Key('^N','\x0e'), _Key('^O','\x0f'),
  _Key('^P','\x10'), _Key('^Q','\x11'), _Key('^R','\x12'),
  _Key('^S','\x13'), _Key('^T','\x14'), _Key('^U','\x15'),
  _Key('^V','\x16'), _Key('^W','\x17'), _Key('^X','\x18'),
  _Key('^Y','\x19'), _Key('^Z','\x1a'),
];

const _rowFn = [
  _Key('F1',_kF1),  _Key('F2',_kF2),  _Key('F3',_kF3),  _Key('F4',_kF4),
  _Key('F5',_kF5),  _Key('F6',_kF6),  _Key('F7',_kF7),  _Key('F8',_kF8),
  _Key('F9',_kF9),  _Key('F10',_kF10), _Key('F11',_kF11), _Key('F12',_kF12),
];

// Un sitio al que se ha saltado dentro del terminal (ssh o pct enter)
class _RemoteLoc {
  final String user;
  final String host; // vacío en un LXC hasta resolver su IP
  final int port;
  final int? lxcId;
  _RemoteLoc.ssh(this.user, this.host, this.port) : lxcId = null;
  _RemoteLoc.lxc(this.lxcId)
      : user = 'root',
        host = '',
        port = 22;
  bool get isLxc => lxcId != null;
  String get label => isLxc ? 'LXC $lxcId' : '$user@$host:$port';
}

// ── Widget ───────────────────────────────────────────────────────────────────
class TerminalScreen extends StatefulWidget {
  final Host host;
  // false → solo devuelve el cuerpo (sin Scaffold/AppBar); usado por TerminalTabsScreen
  final bool showAppBar;
  // Notifica cambios de estado al padre (para la barra de pestañas)
  final void Function(bool connected, String label)? onStatusChanged;
  // false → pestaña oculta: la salida se procesa en tandas lentas
  final bool active;

  const TerminalScreen({
    super.key,
    required this.host,
    this.showAppBar = true,
    this.onStatusChanged,
    this.active = true,
  });

  @override
  State<TerminalScreen> createState() => TerminalScreenState();
}

// Clase pública para acceso vía GlobalKey desde TerminalTabsScreen
class TerminalScreenState extends State<TerminalScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {

  late final Terminal _terminal;
  final FocusNode _focusNode = FocusNode();

  SSHClient? _client;
  SSHSession? _session;
  SSHSocket? _socket;   // referencia al socket TCP para detectar cierre en background
  Pty? _localPty;
  bool _connected = false;
  String _status = 'Connecting…';

  bool get _isLocal => widget.host.authType == 'local';

  int _cols = 80, _rows = 24;

  late final TabController _tabCtrl;
  bool _ctrlActive   = false;
  bool _altActive    = false;
  bool _shiftActive  = false;
  bool _arrowsLock   = false;

  double _fontSize   = 14.0;
  double _scaleStart = 14.0;
  double _swipeX     = 0;
  double _swipeY     = 0;
  static const _kSwipeStep = 22.0;

  // Pinch-zoom y scroll manual via Listener (fuera del gesture arena)
  final Map<int, Offset> _activePointers = {};
  final Map<int, Offset> _dragOrigin     = {};
  final Set<int>         _isDragging     = {};
  double _pinchDist0 = 0;
  static const _kScrollSlop = 8.0;

  // Scroll táctil del histórico del terminal
  final ScrollController _scrollCtrl = ScrollController();

  // Controlador de selección de texto (longPress nativo de xterm)
  late final TerminalController _terminalController;

  // Acumulador de delta para el scroll en alt buffer
  double _altScrollAccum = 0;

  // GlobalKey para acceder a renderTerminal (handles de selección)
  final _terminalViewKey = GlobalKey<TerminalViewState>();

  // Handles de selección táctil
  bool _draggingHandle = false;
  Offset? _selAnchorPx;   // extremo fijo al arrastrar un handle

  // ── API pública ────────────────────────────────────────────────────────────
  bool   get isConnected => _connected;
  String get statusLabel  => _status;
  SSHClient? get sshClient => _client;

  void reconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    _autoReconnect = true;
    _connect();
  }
  void zoomIn()     => _setFontSize(_fontSize + 1);
  void zoomOut()    => _setFontSize(_fontSize - 1);

  // Tamaño de letra persistente (compartido entre pestañas vía caché estática)
  static double? _fontSizeCache;
  Timer? _fontSaveTimer;

  void _setFontSize(double v) {
    setState(() => _fontSize = v.clamp(8.0, 28.0));
    _fontSizeCache = _fontSize;
    _fontSaveTimer?.cancel();
    _fontSaveTimer = Timer(const Duration(milliseconds: 600),
        () => StorageService.saveFontSize(_fontSize));
  }
  void requestFocus() => _focusNode.requestFocus();

  void disconnect() {
    _userClosed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _session?.close();
    _client?.close();
    _closeJumpClients();
    _localPty?.kill();
    _session  = null;
    _client   = null;
    _localPty = null;
    if (mounted) setState(() { _connected = false; _status = 'Disconnected'; });
  }

  // ── Reconexión automática con backoff ───────────────────────────────────────
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _userClosed = false;      // la pestaña se ha cerrado a propósito
  bool _autoReconnect = true;    // se apaga con fallos de auth o huella rechazada
  static const _reconnectDelays = [2, 4, 8, 15, 30];

  void _scheduleReconnect() {
    if (_isLocal || _userClosed || !_autoReconnect || !mounted) return;
    if (_reconnectTimer != null) return;
    final delay = _reconnectDelays[
        _reconnectAttempt.clamp(0, _reconnectDelays.length - 1)];
    _reconnectAttempt++;
    _setStatus(false, Tr.es ? 'Reconectando en ${delay}s (intento $_reconnectAttempt)…' : 'Reconnecting in ${delay}s (attempt $_reconnectAttempt)…');
    _reconnectTimer = Timer(Duration(seconds: delay), () {
      _reconnectTimer = null;
      if (_userClosed || _connected || !mounted) return;
      _connect();
    });
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabCtrl = TabController(length: 4, vsync: this);
    _terminal = Terminal(maxLines: 10000, wordSeparators: _wordSeparators);
    _terminalController = TerminalController();

    // OSC 52: el programa del servidor escribe en el portapapeles del móvil.
    // Así es como las TUI (p. ej. asistentes de código) copian al portapapeles.
    _terminal.onPrivateOSC = (ps, pt) {
      if (ps != '52' || pt.length < 2) return;
      final payload = pt[1];
      if (payload == '?') return; // petición de LECTURA del portapapeles: nunca
      try {
        final text = utf8.decode(base64Decode(base64.normalize(payload)));
        if (text.isEmpty) return;
        Clipboard.setData(ClipboardData(text: text));
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..removeCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(Tr.es
                ? 'Portapapeles actualizado desde el servidor (${text.length} caracteres)'
                : 'Clipboard updated from the server (${text.length} characters)'),
            duration: const Duration(milliseconds: 1600),
            behavior: SnackBarBehavior.floating,
          ));
      } catch (_) {}
    };

    _terminal.onResize = (w, h, pw, ph) {
      if (w > 0 && h > 0) {
        _cols = w; _rows = h;
        _session?.resizeTerminal(w, h);
        _localPty?.resize(h, w); // Pty: rows primero, luego cols
      }
    };

    _terminal.onOutput = (data) {
      if (data.length == 1) {
        if (_ctrlActive) {
          _clearLineBuf();
          final lower = data.toLowerCase().codeUnitAt(0);
          if (lower >= 97 && lower <= 122) {
            _sendBytes(Uint8List.fromList([lower - 96]));
          } else {
            _sendRaw(data);
          }
          if (mounted) setState(() => _ctrlActive = false);
          return;
        }
        if (_altActive) {
          _clearLineBuf();
          _sendBytes(Uint8List.fromList([0x1b, ...utf8.encode(data)]));
          if (mounted) setState(() => _altActive = false);
          return;
        }
        if (_shiftActive && mounted) setState(() => _shiftActive = false);
      }
      _trackInput(data);
      _sendRaw(data);
    };

    if (_cmdHistory == null) {
      StorageService.getCmdHistory().then((h) => _cmdHistory ??= h);
    }

    if (_fontSizeCache != null) {
      _fontSize = _fontSizeCache!;
    } else {
      StorageService.getFontSize().then((v) {
        if (v != null && mounted) {
          _fontSizeCache = v;
          setState(() => _fontSize = v);
        }
      });
    }
    TermThemes.notifier.addListener(_onThemeChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  // ── Autocompletado: historial de comandos + línea en curso ──────────────────
  static List<String>? _cmdHistory; // compartido entre pestañas
  final StringBuffer _lineBuf = StringBuffer();
  List<String> _suggestions = [];

  void _clearLineBuf() {
    _lineBuf.clear();
    _updateSuggestions();
  }

  // Reconstruye la línea que se está escribiendo a partir de las pulsaciones.
  // Ante cualquier cosa rara (escapes, tab, ctrl) se olvida la línea: mejor
  // callar que sugerir mal.
  void _trackInput(String data) {
    if (data == '\r' || data == '\n') { _commitLine(); return; }
    if (data == '\x7f' || data == '\x08') {
      final s = _lineBuf.toString();
      _lineBuf.clear();
      if (s.isNotEmpty) _lineBuf.write(s.substring(0, s.length - 1));
    } else if (data.length == 1 && data.codeUnitAt(0) >= 0x20) {
      _lineBuf.write(data);
    } else {
      _lineBuf.clear();
    }
    _updateSuggestions();
  }

  void _commitLine() {
    final cmd = _lineBuf.toString().trim();
    _clearLineBuf();
    if (cmd.isEmpty) return;
    _trackJump(cmd);
    if (cmd.length < 3) return;
    final h = _cmdHistory ??= [];
    h.remove(cmd);
    h.insert(0, cmd);
    if (h.length > 200) h.removeRange(200, h.length);
    StorageService.saveCmdHistory(h);
  }

  // ── Dónde estoy: saltos hechos a mano dentro del terminal ──────────────────
  // `ssh usuario@maquina` y `pct enter <id>` (o `pct exec <id> -- bash`) se
  // apilan; el botón SFTP ofrece también ese sitio. Para un LXC la IP se
  // resuelve preguntando al host por la conexión ya abierta (canal aparte).
  // `exit`/`logout` deshace el salto.
  final List<_RemoteLoc> _remoteStack = [];

  // Flags de ssh que llevan valor detrás (para no confundirlo con el destino)
  static const _sshValueFlags = {
    '-i', '-o', '-L', '-R', '-D', '-J', '-F', '-E', '-b', '-c', '-m', '-W'
  };

  void _trackJump(String cmd) {
    final parts = cmd.split(RegExp(r'\s+'));
    if (parts.isEmpty) return;
    if (parts[0] == 'exit' || parts[0] == 'logout') {
      if (_remoteStack.isNotEmpty) _remoteStack.removeLast();
      return;
    }
    if (parts[0] == 'pct') {
      int? id;
      if (parts.length == 3 && parts[1] == 'enter') {
        id = int.tryParse(parts[2]);
      } else if (parts.length == 5 &&
          parts[1] == 'exec' &&
          parts[3] == '--' &&
          const {'bash', 'sh', 'zsh', 'ash'}.contains(parts[4])) {
        id = int.tryParse(parts[2]);
      }
      if (id != null) _remoteStack.add(_RemoteLoc.lxc(id));
      return;
    }
    if (parts[0] != 'ssh') return;
    String? target;
    String? userFlag;
    var port = 22;
    var i = 1;
    while (i < parts.length) {
      final p = parts[i];
      if (p == '-p' && i + 1 < parts.length) {
        port = int.tryParse(parts[i + 1]) ?? 22;
        i += 2;
      } else if (p == '-l' && i + 1 < parts.length) {
        userFlag = parts[i + 1];
        i += 2;
      } else if (_sshValueFlags.contains(p) && i + 1 < parts.length) {
        i += 2;
      } else if (p.startsWith('-')) {
        i++;
      } else {
        target = p;
        i++;
        break;
      }
    }
    if (target == null) return;
    if (i < parts.length) return; // "ssh host comando" no cambia de sitio
    final m = RegExp(r'^(?:([\w.\-]+)@)?([\w.\-]+)$').firstMatch(target);
    if (m == null) return;
    _remoteStack.add(_RemoteLoc.ssh(
      m.group(1) ?? userFlag ?? 'root',
      m.group(2)!,
      port,
    ));
  }

  void _updateSuggestions() {
    final prefix = _lineBuf.toString();
    final out = <String>[];
    if (prefix.trim().length >= 2) {
      for (final c in _cmdHistory ?? const <String>[]) {
        if (c.startsWith(prefix) && c != prefix) {
          out.add(c);
          if (out.length >= 6) break;
        }
      }
    }
    if (!mounted) return;
    if (out.length != _suggestions.length ||
        !out.asMap().entries.every((e) => _suggestions[e.key] == e.value)) {
      setState(() => _suggestions = out);
    }
  }

  // Completa: manda solo lo que falta (la línea del servidor ya tiene el prefijo)
  void _applySuggestion(String full) {
    final prefix = _lineBuf.toString();
    if (!full.startsWith(prefix)) return;
    _sendRaw(full.substring(prefix.length));
    _lineBuf.clear();
    _lineBuf.write(full);
    _updateSuggestions();
    _refocus();
  }

  @override
  void dispose() {
    _userClosed = true;
    TermThemes.notifier.removeListener(_onThemeChanged);
    _fontSaveTimer?.cancel();
    _reconnectTimer?.cancel();
    _flushTimer?.cancel();
    _stopAutoScroll();
    _stopFling();
    WidgetsBinding.instance.removeObserver(this);
    _focusNode.dispose();
    _scrollCtrl.dispose();
    _terminalController.dispose();
    _session?.close();
    _client?.close();
    _closeJumpClients();
    _socket = null;
    _localPty?.kill();
    _tabCtrl.dispose();
    if (_wasConnected && !_isLocal) {
      _wasConnected = false;
      SshKeepaliveService.onDisconnect();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isLocal) {
      // Al volver a primer plano, fuerza un repintado para mostrar el estado
      // real (el overlay de reconexión si la sesión cayó mientras en background).
      if (mounted) setState(() {});
      if (_connected) {
        // Intenta un write de 0 bytes para que dartssh2 detecte un socket muerto
        // y dispare los handlers de session.done / socket.done.
        try {
          _session?.stdin.add(Uint8List(0));
        } catch (_) {
          _setStatus(false, tr('Session lost'));
          _writeInfo('\r\n[Session lost in the background]\r\n');
          _scheduleReconnect();
        }
      } else if (!_userClosed && _autoReconnect && _reconnectTimer != null) {
        // Al volver a la app con una reconexión pendiente: reintento inmediato
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        _connect();
      }
    }
  }

  // Huella cambiada: diálogo compartido; mientras se decide, sin reintentos
  Future<bool> _onHostkeyMismatch(Host h, String stored, String current) async {
    if (!mounted) return false;
    _autoReconnect = false; // no reintentar en bucle contra un host sospechoso
    final ok =
        await SshConnectService.showMismatchDialog(context, h, stored, current);
    if (ok) _autoReconnect = true;
    return ok;
  }

  // Clientes intermedios de la cadena ProxyJump (se cierran al desconectar)
  final List<SSHClient> _jumpClients = [];

  void _closeJumpClients() {
    for (final c in _jumpClients) {
      try { c.close(); } catch (_) {}
    }
    _jumpClients.clear();
  }

  // ── Conexión (SSH o local) ─────────────────────────────────────────────────
  Future<void> _connect() async {
    if (_isLocal) { await _connectLocal(); return; }
    final h = widget.host;
    _setStatus(false, tr('Connecting…'));
    _writeInfo('Connecting to ${h.username}@${h.hostname}:${h.port}…\r\n');
    _closeJumpClients();
    try {
      final conn = await SshConnectService.connect(
        h,
        onHostkeyMismatch: _onHostkeyMismatch,
        onInfo: (m) => _writeInfo('$m\r\n'),
      );
      final socket = conn.socket;
      _socket = socket;
      _client = conn.client;
      _jumpClients.addAll(conn.jumpClients);
      _session = await _client!.shell(
        pty: SSHPtyConfig(type: 'xterm-256color', width: _cols, height: _rows),
      );
      _session!.stdout
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(_feed);
      _session!.stderr
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(_feed);
      // session.done: cierre limpio del shell (exit, etc.) → no se reintenta
      _session!.done.then((_) {
        if (_userClosed) return;
        _writeInfo('\r\n[Session closed]\r\n');
        _closeJumpClients();
        _remoteStack.clear();
        _setStatus(false, tr('Disconnected'));
      });
      // socket.done: cierre TCP (corte de red, servidor reiniciado, etc.)
      socket.done.then((_) {
        if (_userClosed) return;
        _writeInfo('\r\n[TCP connection closed]\r\n');
        _closeJumpClients();
        _setStatus(false, tr('Disconnected'));
        _socket = null;
        _scheduleReconnect();
      }).catchError((_) {
        if (_userClosed) return;
        _writeInfo('\r\n[Network error]\r\n');
        _closeJumpClients();
        _setStatus(false, tr('Network error'));
        _socket = null;
        _scheduleReconnect();
      });
      _setStatus(true, h.hostname);
      _reconnectAttempt = 0;
      _remoteStack.clear();
      // Sesión persistente: engancha (o crea) la sesión tmux "hssh". Al
      // reconectar se vuelve exactamente donde se estaba (sucedáneo de mosh).
      void sendCmd(String cmd, int delayMs) {
        Future.delayed(Duration(milliseconds: delayMs), () {
          if (_session != null && _connected) {
            _session!.stdin.add(Uint8List.fromList(utf8.encode('$cmd\n')));
          }
        });
      }
      final cmd = h.startupCmd.trim();
      if (h.useTmux) {
        // `new -A`: si la sesión existe solo engancha (e ignora el comando);
        // si no, la crea ejecutando el comando de arranque y deja shell al salir.
        final inner = cmd.isEmpty
            ? ''
            : " '${cmd.replaceAll("'", "'\\''")}; exec \$SHELL'";
        sendCmd('tmux new -A -s hssh$inner', 300);
      } else if (cmd.isNotEmpty) {
        sendCmd(cmd, 300);
      }
    } catch (e) {
      _writeInfo('\r\n[Error: $e]\r\n');
      final msg = e.toString().toLowerCase();
      final authFail = msg.contains('auth') || msg.contains('hostkey');
      _setStatus(false, authFail ? tr('Authentication failed') : 'Error');
      // Con fallo de auth o huella rechazada no tiene sentido reintentar solo
      if (!authFail) _scheduleReconnect();
    }
  }

  Future<void> _connectLocal() async {
    _setStatus(false, tr('Starting…'));
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final pty = Pty.start(
        '/system/bin/sh',
        arguments: ['-i'],
        environment: {
          'TERM': 'xterm-256color',
          'COLORTERM': 'truecolor',
          'HOME': appDir.path,
          'PATH': '/system/bin:/system/xbin:/data/local/tmp',
        },
        columns: _cols,
        rows: _rows,
        workingDirectory: appDir.path,
      );
      _localPty = pty;

      pty.output
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(_feed);

      pty.exitCode.then((code) {
        _writeInfo('\r\n[Shell ended ($code) — tap ↺ to restart]\r\n');
        _setStatus(false, tr('Ended'));
        _localPty = null;
      });

      _setStatus(true, 'Local');
    } catch (e) {
      _writeInfo('\r\n[Error: $e]\r\n');
      _setStatus(false, 'Error');
    }
  }

  bool _wasConnected = false;

  void _setStatus(bool connected, String label) {
    if (!mounted) return;
    setState(() { _connected = connected; _status = label; });
    widget.onStatusChanged?.call(connected, label);
    // Gestiona el foreground service para que Android no cierre la sesión SSH.
    if (!_isLocal) {
      if (connected && !_wasConnected) {
        _wasConnected = true;
        SshKeepaliveService.onConnect();
      } else if (!connected && _wasConnected) {
        _wasConnected = false;
        SshKeepaliveService.onDisconnect();
      }
    }
  }

  void _writeInfo(String msg) {
    _flush();
    _terminal.write('\x1b[90m$msg\x1b[0m');
  }

  // Por SSH llegan muchos trozos pequeños por frame: se acumulan y se escriben
  // una vez al empezar el siguiente frame. El Timer cubre la app en segundo
  // plano, donde no hay frames.
  final _pending = StringBuffer();
  bool _flushScheduled = false;
  Timer? _flushTimer;

  void _feed(String data) {
    _pending.write(data);
    if (_flushScheduled) return;
    _flushScheduled = true;
    if (widget.active) {
      SchedulerBinding.instance.scheduleFrameCallback((_) => _flush());
      SchedulerBinding.instance.scheduleFrame();
      _flushTimer = Timer(const Duration(milliseconds: 50), _flush);
    } else {
      // Pestaña oculta: tanda lenta y sin forzar frames.
      _flushTimer = Timer(const Duration(milliseconds: 200), _flush);
    }
  }

  @override
  void didUpdateWidget(covariant TerminalScreen old) {
    super.didUpdateWidget(old);
    // Al volver a esta pestaña, aplicar en el acto lo acumulado.
    if (widget.active && !old.active) _flush();
  }

  void _flush() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _flushScheduled = false;
    if (_pending.isEmpty || !mounted) return;
    var data = _pending.toString();
    _pending.clear();
    // Retener un CSI incompleto al final de la tanda: si una secuencia de
    // estilo llega partida en dos, el traductor no la vería entera y se
    // colarían estilos falsos (p. ej. subrayados).
    final cut = _incompleteCsiStart(data);
    if (cut >= 0) {
      _pending.write(data.substring(cut));
      data = data.substring(0, cut);
    }
    if (data.isEmpty) return;
    final wasAlt = _terminal.isUsingAltBuffer;
    _terminal.write(_fixSgr(data));
    // Al salir de la pantalla alternativa, no arrastrar estilos a la shell.
    if (wasAlt && !_terminal.isUsingAltBuffer) _terminal.write('\x1b[0m');
  }

  /// Índice donde empieza una secuencia CSI sin terminar al final de [s],
  /// o -1 si no la hay.
  static int _incompleteCsiStart(String s) {
    final esc = s.lastIndexOf('\x1b');
    if (esc < 0 || s.length - esc > 64) return -1;
    if (esc == s.length - 1) return esc; // ESC suelto al final
    if (s.codeUnitAt(esc + 1) != 0x5b) return -1; // no es CSI «[»
    for (var i = esc + 2; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c >= 0x40 && c <= 0x7e) return -1; // tiene byte final: completa
    }
    return esc;
  }

  static final _sgrRe = RegExp(r'\x1b\[([0-9;:]*)m');

  // xterm 4.0.0 no entiende subparámetros con ':' (junta los dígitos: 4:0 → 40)
  // ni el SGR 58 (lee sus argumentos como estilos sueltos, p. ej. un 4 =
  // subrayado). Se reescriben a la forma con ';' que sí entiende.
  static String _fixSgr(String s) {
    if (!s.contains('\x1b[')) return s;
    // Solo reconstruir el texto si hay algo que traducir: evita fabricar
    // basura (y pausas del GC) con cada ráfaga de salida.
    var needsFix = false;
    for (final m in _sgrRe.allMatches(s)) {
      final body = m[1]!;
      if (body.contains(':') || body.contains('58')) {
        needsFix = true;
        break;
      }
    }
    if (!needsFix) return s;
    return s.replaceAllMapped(_sgrRe, (m) {
      final body = m[1]!;
      if (!body.contains(':') && !body.contains('58')) return m[0]!;
      final t = body.split(';');
      final out = <String>[];
      for (var i = 0; i < t.length; i++) {
        final p = t[i];
        if (p.contains(':')) {
          final sub = p.split(':');
          final v = sub.where((x) => x.isNotEmpty).toList();
          switch (sub[0]) {
            case '4':
              out.add(sub.length > 1 && sub[1] == '0' ? '24' : '4');
            case '38':
            case '48':
              if (v.length >= 3 && v[1] == '5') {
                out.add('${v[0]};5;${v[2]}');
              } else if (v.length >= 5 && v[1] == '2') {
                out.add('${v[0]};2;${v.sublist(v.length - 3).join(';')}');
              }
          }
          continue;
        }
        if (p == '38' || p == '48' || p == '58') {
          final mode = i + 1 < t.length ? t[i + 1] : '';
          final n = mode == '5' ? 2 : mode == '2' ? 4 : 0;
          if (p != '58') out.addAll(t.sublist(i, (i + n + 1).clamp(0, t.length)));
          i += n;
          continue;
        }
        if (p == '59') continue;
        out.add(p);
      }
      return out.isEmpty ? '' : '\x1b[${out.join(';')}m';
    });
  }

  void _sendBytes(Uint8List bytes) {
    if (_isLocal) {
      _localPty?.write(bytes);
    } else {
      _session?.stdin.add(bytes);
    }
  }

  void _sendRaw(String data) =>
      _sendBytes(Uint8List.fromList(utf8.encode(data)));

  void _refocus() => _focusNode.requestFocus();

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  // Abrir con un toque las URLs que aparezcan en la salida del terminal
  static final _urlRe = RegExp(r'https?://[^\s' r"'" r'"<>\[\]{}|\\^`]+');

  Future<void> _maybeOpenUrl(Offset pos) async {
    try {
      final render = _terminalViewKey.currentState?.renderTerminal;
      if (render == null) return;
      final cell = render.getCellOffset(pos);
      if (cell.y >= _terminal.buffer.lines.length) return;
      final line = _terminal.buffer.lines[cell.y].getText();
      for (final m in _urlRe.allMatches(line)) {
        if (cell.x < m.start || cell.x >= m.end) continue;
        var url = m.group(0)!;
        while (url.isNotEmpty && '.,;:)]'.contains(url[url.length - 1])) {
          url = url.substring(0, url.length - 1);
        }
        final ok = await launchUrl(Uri.parse(url),
            mode: LaunchMode.externalApplication);
        if (!ok && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(tr('Could not open the link'))));
        }
        return;
      }
    } catch (_) {}
  }

  // Pantalla completa: oculta appbar, pestañas y barra de estado de Android
  void _toggleFullscreen() {
    final hub = TabsHub.instance;
    hub.fullscreen = !hub.fullscreen;
    if (hub.fullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
          overlays: SystemUiOverlay.values);
    }
    hub.refresh();
    if (mounted) setState(() {});
  }

  void _sendKey(_Key key) {
    _clearLineBuf(); // flechas/Esc/etc. desalinean la línea rastreada
    String seq = key.seq;
    // Shift+Tab: independientemente del botón pulsado, si SHIFT activo + TAB
    if (_shiftActive && seq == _kTab) seq = _kShTab;
    if (_altActive)  { seq = '\x1b$seq'; setState(() => _altActive  = false); }
    if (_ctrlActive) { setState(() => _ctrlActive = false); }
    if (_shiftActive && seq != _kShTab) setState(() => _shiftActive = false);
    _sendRaw(seq);
    _refocus();
  }

  void _copySelection() {
    final sel = _terminalController.selection;
    if (sel == null) return;
    final text = _terminal.buffer.getText(sel);
    Clipboard.setData(ClipboardData(text: text));
    _terminalController.clearSelection();
  }

  // Copia la selección como UNA sola línea: filas recortadas y unidas con
  // espacios. Para comandos que una TUI (p. ej. Claude Code) parte en varias
  // filas dibujadas: el terminal no puede saber que eran un párrafo.
  void _copySelectionJoined() {
    final sel = _terminalController.selection;
    if (sel == null) return;
    final text = _terminal.buffer
        .getText(sel)
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .join(' ');
    Clipboard.setData(ClipboardData(text: text));
    _terminalController.clearSelection();
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(tr('Copied as one line')),
        duration: const Duration(milliseconds: 1200),
        behavior: SnackBarBehavior.floating,
      ));
  }

  // ── Scroll + inercia ─────────────────────────────────────────────────────────
  void _applyScrollDelta(double delta, Offset at) {
    if (_terminal.isUsingAltBuffer) {
      // Alt buffer: rueda al proceso. Dedo abajo = wheelUp,
      // igual que el histórico (el contenido sigue al dedo).
      _altScrollAccum += delta;
      const step = 20.0;
      while (_altScrollAccum.abs() >= step) {
        final up = _altScrollAccum > 0;
        _sendWheel(up, at);
        _altScrollAccum += up ? -step : step;
      }
    } else if (_scrollCtrl.hasClients) {
      final pos = _scrollCtrl.position;
      if (pos.hasContentDimensions && pos.maxScrollExtent > 0) {
        _scrollCtrl.jumpTo(
            (pos.pixels - delta).clamp(0.0, pos.maxScrollExtent));
      }
    }
  }

  // Inercia al soltar: sigue deslizando y frena exponencialmente (~0,3 s de
  // constante), como las listas de Android. Tocar la pantalla la corta.
  VelocityTracker? _vTracker;
  Timer? _flingTimer;
  double _flingVel = 0; // px/s, positivo = dedo hacia abajo

  void _startFling(double velocity, Offset at) {
    _flingVel = velocity.clamp(-8000.0, 8000.0);
    _flingTimer?.cancel();
    _flingTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted) {
        _stopFling();
        return;
      }
      _applyScrollDelta(_flingVel * 0.016, at);
      _flingVel *= 0.94;
      if (_flingVel.abs() < 60) {
        _stopFling();
        return;
      }
      if (!_terminal.isUsingAltBuffer && _scrollCtrl.hasClients) {
        final p = _scrollCtrl.position;
        if (p.pixels <= 0 || p.pixels >= p.maxScrollExtent) _stopFling();
      }
    });
  }

  void _stopFling() {
    _flingTimer?.cancel();
    _flingTimer = null;
    _flingVel = 0;
  }

  // ── Autoscroll al arrastrar el asa inferior hasta el borde ──────────────────
  // Solo en el buffer normal (histórico real): la selección sigue a su texto,
  // como en una web. En alt buffer (TUIs) no hay histórico que recorrer.
  Timer? _autoScrollTimer;
  Offset? _autoScrollPos;

  void _updateAutoScroll(Offset fingerPos, Size viewSize) {
    _autoScrollPos = fingerPos;
    if (_terminal.isUsingAltBuffer || fingerPos.dy <= viewSize.height - 56) {
      _stopAutoScroll();
      return;
    }
    _autoScrollTimer ??= Timer.periodic(
        const Duration(milliseconds: 150), (_) => _autoScrollTick());
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  void _autoScrollTick() {
    final pos = _autoScrollPos;
    if (pos == null || !mounted) {
      _stopAutoScroll();
      return;
    }
    try {
      final render = _terminalViewKey.currentState!.renderTerminal;
      if (_scrollCtrl.hasClients) {
        final p = _scrollCtrl.position;
        if (p.maxScrollExtent > 0) {
          _scrollCtrl.jumpTo(
              (p.pixels + render.lineHeight).clamp(0.0, p.maxScrollExtent));
        }
      }
      // Reextender hasta el dedo partiendo del inicio actual de la selección
      final sel = _terminalController.selection?.normalized;
      if (sel != null) {
        final beginPx = render
            .getOffset(sel.begin)
            .translate(render.cellSize.width / 2, render.lineHeight / 2);
        render.selectCharacters(beginPx, pos);
      }
    } catch (_) {}
  }

  // xterm 4.0.0 codifica la rueda como 68/69 (= Shift+rueda) y no reporta
  // nada con estado up; por eso se genera aquí con los códigos estándar 64/65.
  void _sendWheel(bool up, Offset localPos) {
    if (!_terminal.mouseMode.reportScroll) {
      _sendRaw(up ? _kPgUp : _kPgDown);
      return;
    }
    var x = 1, y = 1;
    try {
      final cell = _terminalViewKey.currentState!.renderTerminal
          .getCellOffset(localPos);
      x = (cell.x + 1).clamp(1, _cols);
      y = (cell.y + 1).clamp(1, _rows);
    } catch (_) {}
    final id = up ? 64 : 65;
    switch (_terminal.mouseReportMode) {
      case MouseReportMode.sgr:
        _sendRaw('\x1b[<$id;$x;${y}M');
      case MouseReportMode.urxvt:
        _sendRaw('\x1b[${32 + id};$x;${y}M');
      case MouseReportMode.normal:
      case MouseReportMode.utf:
        _sendRaw('\x1b[M${String.fromCharCode(32 + id)}'
            '${String.fromCharCode(32 + x)}${String.fromCharCode(32 + y)}');
    }
  }

  // ── Copiar pantalla acumulativo ────────────────────────────────────────────
  // Pulsar copia lo visible; volver a pulsar tras bajar AÑADE lo nuevo al
  // portapapeles quitando el solape. Así se copia más de una pantalla incluso
  // en TUIs de pantalla completa (alt buffer, sin histórico).
  String _copyAccum = '';
  DateTime? _copyAccumAt;

  String _visibleText() {
    try {
      final render = _terminalViewKey.currentState!.renderTerminal;
      final first = render.getCellOffset(Offset.zero).y;
      final lines = _terminal.buffer.lines;
      final last = (first + _rows - 1).clamp(0, lines.length - 1);
      final out = <String>[];
      for (var y = first; y <= last; y++) {
        out.add(lines[y].getText().trimRight());
      }
      while (out.isNotEmpty && out.last.isEmpty) {
        out.removeLast();
      }
      return out.join('\n');
    } catch (_) {
      return '';
    }
  }

  /// Une [extra] al final de [base] quitando el solape: las últimas líneas de
  /// base que coinciden con las primeras de extra no se repiten.
  static String _mergeOverlap(String base, String extra) {
    final a = base.split('\n');
    final b = extra.split('\n');
    final maxK = a.length < b.length ? a.length : b.length;
    for (var k = maxK; k > 0; k--) {
      var match = true;
      for (var i = 0; i < k; i++) {
        if (a[a.length - k + i] != b[i]) {
          match = false;
          break;
        }
      }
      if (match) {
        if (k == b.length) return base;
        return '$base\n${b.sublist(k).join('\n')}';
      }
    }
    return '$base\n$extra';
  }

  void _copyScreen() {
    final text = _visibleText();
    if (text.trim().isEmpty) return;
    final now = DateTime.now();
    final chain = _copyAccumAt != null &&
        now.difference(_copyAccumAt!) < const Duration(seconds: 90) &&
        _copyAccum.isNotEmpty;
    _copyAccum = chain ? _mergeOverlap(_copyAccum, text) : text;
    _copyAccumAt = now;
    Clipboard.setData(ClipboardData(text: _copyAccum));
    if (!mounted) return;
    final n = _copyAccum.split('\n').length;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(chain
            ? (Tr.es ? 'Añadido al portapapeles ($n líneas en total)' : 'Appended to clipboard ($n lines total)')
            : (Tr.es ? 'Pantalla copiada — baja y vuelve a pulsar para añadir' : 'Screen copied — scroll and tap again to append')),
        duration: const Duration(milliseconds: 1400),
        behavior: SnackBarBehavior.floating,
      ));
  }

  // Separadores de palabra para la pulsación larga: los de xterm más signos
  // habituales y los bordes de caja de las tablas (si no, la selección se
  // traga los │ ─ y las celdas vecinas).
  static final Set<int> _wordSeparators = {
    0,
    ...' .:-\\"*+/|()[]{}<>,;=\'!?'.codeUnits,
    for (var c = 0x2500; c <= 0x25FF; c++) c, // bordes de caja y bloques
  };

  // Selección que había al apoyar cada dedo: si durante la pulsación nace una
  // selección (pulsación larga), ese dedo extiende la selección y no scrollea.
  final _selAtDown = <int, Object?>{};

  // Teclado solo por botón: con readOnly xterm no abre el teclado al tocar.
  bool _kbOn = false;
  bool _kbWasVisible = false;

  // View.of y no MediaQuery: el Scaffold quita los viewInsets al body.
  bool get _keyboardVisible => View.of(context).viewInsets.bottom > 0;

  void _toggleKeyboard() {
    setState(() => _kbOn = !_kbOn);
    if (_kbOn) {
      _focusNode.requestFocus();
    } else {
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    }
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final visible = _keyboardVisible;
    // Cerrado con el gesto atrás de Android: volver a modo sin teclado.
    final closedBySystem = _kbWasVisible && !visible && _kbOn;
    _kbWasVisible = visible;
    if (closedBySystem) setState(() => _kbOn = false);
  }

  // ── SFTP: a la conexión original, o a donde hayas saltado con ssh ──────────
  Future<void> _openSftp() async {
    if (_client == null) return;
    if (_remoteStack.isEmpty) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => SftpScreen(client: _client!)));
      return;
    }
    final here = _remoteStack.last;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Text(tr('Open SFTP of…'),
                style: TextStyle(
                    color: kTextPri,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            ListTile(
              leading: const Icon(Icons.my_location,
                  color: kAccent, size: 22),
              title: Text(here.label,
                  style: const TextStyle(color: kTextPri, fontSize: 15)),
              subtitle: Text(
                  here.isLxc
                      ? tr('Where you are now (pct — IP will be resolved)')
                      : tr('Where you are now (ssh jump)'),
                  style: const TextStyle(color: kAccent, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                if (here.isLxc) {
                  _sftpToLxc(here.lxcId!);
                } else {
                  _sftpTo((user: here.user, host: here.host, port: here.port));
                }
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.dns_outlined, color: kTextSec, size: 22),
              title: Text(widget.host.name,
                  style: const TextStyle(color: kTextPri, fontSize: 15)),
              subtitle: Text(tr('The original connection of this tab'),
                  style: TextStyle(color: kTextSec, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => SftpScreen(client: _client!)));
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  // Resuelve la IP de un LXC preguntando al host por la conexión ya abierta
  // (canal exec aparte: no toca lo que ves en el terminal). Primero mira la
  // config del contenedor (ip=x.x.x.x); si va por DHCP, se lo pregunta al
  // propio contenedor con hostname -I.
  Future<void> _sftpToLxc(int id) async {
    if (_client == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${Tr.es ? 'Resolviendo la IP del LXC' : 'Resolving the IP of LXC'} $id…'),
      duration: const Duration(milliseconds: 1200),
    ));
    try {
      String? ip;
      final cfg = utf8.decode(
          await _client!.run('pct config $id 2>/dev/null'),
          allowMalformed: true);
      ip = RegExp(r'ip=(\d+\.\d+\.\d+\.\d+)').firstMatch(cfg)?.group(1);
      if (ip == null) {
        final out = utf8.decode(
            await _client!.run('pct exec $id -- hostname -I 2>/dev/null'),
            allowMalformed: true);
        ip = RegExp(r'(\d+\.\d+\.\d+\.\d+)').firstMatch(out)?.group(1);
      }
      if (ip == null) {
        throw Exception('no IP in the config and no answer from the container');
      }
      if (!mounted) return;
      await _sftpTo((user: 'root', host: ip, port: 22));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${Tr.es ? 'No se pudo resolver el LXC' : 'Could not resolve LXC'} $id: $e'),
      ));
    }
  }

  Future<void> _sftpTo(({String user, String host, int port}) t) async {
    // Si coincide con un host guardado, se usa tal cual (sus credenciales);
    // si no, se pide la contraseña y se monta una conexión temporal.
    final hosts = await StorageService.getHosts();
    final idx = hosts.indexWhere((h) =>
        h.hostname == t.host && h.port == t.port && h.username == t.user);
    if (!mounted) return;
    if (idx >= 0) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => SftpScreen(host: hosts[idx])));
      return;
    }
    final pwCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('SFTP ${Tr.es ? 'a' : 'to'} ${t.user}@${t.host}',
            style: const TextStyle(color: kTextPri, fontSize: 16)),
        content: TextField(
          controller: pwCtrl,
          obscureText: true,
          autofocus: true,
          style: const TextStyle(color: kTextPri),
          decoration: InputDecoration(labelText: tr('Password')),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancel'), style: TextStyle(color: kTextSec)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Connect'),
                style:
                    TextStyle(color: kAccent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final temp = Host(
      name: '${t.user}@${t.host}',
      hostname: t.host,
      port: t.port,
      username: t.user,
    );
    if (pwCtrl.text.isNotEmpty) {
      await StorageService.savePassword(temp.id, pwCtrl.text);
    }
    if (!mounted) return;
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => SftpScreen(host: temp)));
  }

  Future<void> _openSnippets() async {
    final cmd = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const SnippetsScreen(selectMode: true)),
    );
    if (cmd != null && cmd.isNotEmpty) {
      _clearLineBuf();
      _sendRaw(cmd);
    }
    _refocus();
  }

  // ── Widgets ────────────────────────────────────────────────────────────────
  Widget _keyBtn(_Key key, {Color? labelColor}) {
    return GestureDetector(
      onTap: () => _sendKey(key),
      child: Container(
        constraints: const BoxConstraints(minWidth: 42),
        height: 38,
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF1E2740), borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: key.icon != null
            ? Icon(key.icon, size: 18, color: labelColor ?? kTextPri)
            : Text(key.label,
                style: TextStyle(
                    fontSize: 13, color: labelColor ?? kTextPri,
                    fontFamily: 'JetBrainsMono', height: 1)),
      ),
    );
  }

  Widget _modBtn(String label, bool active, VoidCallback onTap, {Color? activeColor}) {
    final color = activeColor ?? kAccent;
    return GestureDetector(
      onTap: () { onTap(); _refocus(); },
      child: Container(
        constraints: const BoxConstraints(minWidth: 38),
        height: 30,
        margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 3),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.22) : const Color(0xFF1E2740),
          borderRadius: BorderRadius.circular(6),
          border: active ? Border.all(color: color.withOpacity(0.7)) : null,
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600,
                color: active ? color : kTextSec, height: 1)),
      ),
    );
  }

  Widget _buildKeyboard() {
    return Container(
      color: kSurface,
      // Cubre la zona del gesto de navegación con el color de la barra
      // (cuando el teclado está abierto, padding.bottom pasa a 0 solo)
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Sugerencias del historial mientras se escribe (estilo Termius)
          if (_suggestions.isNotEmpty)
            Container(
              height: 34,
              color: const Color(0xFF0B101E),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                itemCount: _suggestions.length,
                itemBuilder: (_, i) {
                  final s = _suggestions[i];
                  return GestureDetector(
                    onTap: () => _applySuggestion(s),
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 3, vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF17203A),
                        borderRadius: BorderRadius.circular(6),
                        border:
                            Border.all(color: kAccent2.withOpacity(0.35)),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        s.length > 42 ? '${s.substring(0, 40)}…' : s,
                        style: const TextStyle(
                            fontSize: 12,
                            color: kTextPri,
                            fontFamily: 'JetBrainsMono',
                            height: 1),
                      ),
                    ),
                  );
                },
              ),
            ),
          Container(
            height: 36,
            color: const Color(0xFF0E1320),
            child: Row(
              children: [
                const SizedBox(width: 4),
                _modBtn('ALT',   _altActive,   () => setState(() => _altActive   = !_altActive)),
                _modBtn('CTRL',  _ctrlActive,  () => setState(() => _ctrlActive  = !_ctrlActive)),
                _modBtn('SHIFT', _shiftActive, () => setState(() => _shiftActive = !_shiftActive)),
                _modBtn('⇅↔', _arrowsLock, () => setState(() => _arrowsLock = !_arrowsLock),
                    activeColor: const Color(0xFFFFD93D)),
                const Spacer(),
                GestureDetector(
                  onTap: _toggleFullscreen,
                  child: Container(
                    height: 30,
                    margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E2740), borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      TabsHub.instance.fullscreen
                          ? Icons.fullscreen_exit
                          : Icons.fullscreen,
                      size: 20,
                      color: TabsHub.instance.fullscreen ? kAccent : kTextSec,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _copyScreen,
                  child: Container(
                    height: 30,
                    margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E2740), borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.copy_all, size: 20, color: kTextSec),
                  ),
                ),
                GestureDetector(
                  onTap: _toggleKeyboard,
                  child: Container(
                    height: 30,
                    margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E2740), borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      _kbOn ? Icons.keyboard_hide : Icons.keyboard,
                      size: 20, color: _kbOn ? kAccent : kTextSec,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _openSnippets,
                  child: Container(
                    height: 30,
                    margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E2740), borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: Text(tr('{}'),
                        style: const TextStyle(
                            fontSize: 14, color: kTextSec, height: 1)),
                  ),
                ),
                if (_connected && _client != null)
                  GestureDetector(
                    onTap: _openSftp,
                    child: Container(
                      height: 30,
                      margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 3),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E2740), borderRadius: BorderRadius.circular(6),
                      ),
                      alignment: Alignment.center,
                      child: Text(tr('SFTP'),
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600,
                              color: kAccent2, height: 1)),
                    ),
                  ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          Container(
            height: 28,
            color: const Color(0xFF0E1320),
            child: TabBar(
              controller: _tabCtrl,
              labelColor: kAccent,
              unselectedLabelColor: kTextSec,
              indicatorColor: kAccent,
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: 'Nav',  height: 28),
                Tab(text: 'Sym',  height: 28),
                Tab(text: 'Ctrl', height: 28),
                Tab(text: 'Fn',   height: 28),
              ],
            ),
          ),
          SizedBox(
            height: 46,
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _scrollRow(_rowNav),
                _scrollRow(_rowSym),
                _scrollRow(_rowCtrl, labelColor: const Color(0xFFFF9F43)),
                _scrollRow(_rowFn),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _scrollRow(List<_Key> keys, {Color? labelColor}) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(children: keys.map((k) => _keyBtn(k, labelColor: labelColor)).toList()),
    );
  }

  // ── Cuerpo reutilizable ────────────────────────────────────────────────────
  Widget _buildBody() {
    // NeverScrollable desactiva los Scrollable internos de xterm (histórico y el
    // InfiniteScrollView del alt buffer); todo el scroll lo hace nuestro Listener.
    final termView = RepaintBoundary(
      child: ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        physics: const NeverScrollableScrollPhysics(),
      ),
      child: TerminalView(
      _terminal,
      key: _terminalViewKey,
      controller: _terminalController,
      focusNode: _focusNode,
      theme: TermThemes.current,
      scrollController: _scrollCtrl,
      readOnly: !_kbOn,
      textStyle: TerminalStyle(
        fontSize: _fontSize,
        fontFamily: 'JetBrainsMono',
        fontFamilyFallback: const ['monospace'],
      ),
      autofocus: true,
      backgroundOpacity: 1.0,
      keyboardType: TextInputType.visiblePassword,
      deleteDetection: true,
      onSecondaryTapDown: (_, __) {
        Clipboard.getData('text/plain').then((data) {
          if (data?.text != null) _sendRaw(data!.text!);
        });
      },
    ),
    ),
    );

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (e) {
                  _stopFling(); // tocar frena la inercia
                  _activePointers[e.pointer] = e.localPosition;
                  _dragOrigin[e.pointer]     = e.localPosition;
                  _selAtDown[e.pointer]      = _terminalController.selection;
                  if (_activePointers.length == 1) {
                    _vTracker = VelocityTracker.withKind(e.kind)
                      ..addPosition(e.timeStamp, e.localPosition);
                  } else if (_activePointers.length == 2) {
                    _vTracker = null;
                    _isDragging.clear();
                    final pts = _activePointers.values.toList();
                    _pinchDist0 = (pts[0] - pts[1]).distance;
                    _scaleStart = _fontSize;
                  }
                },
                onPointerMove: (e) {
                  final prev = _activePointers[e.pointer];
                  _activePointers[e.pointer] = e.localPosition;

                  if (_activePointers.length == 2 && _pinchDist0 > 0) {
                    final pts = _activePointers.values.toList();
                    final dist = (pts[0] - pts[1]).distance;
                    _setFontSize(_scaleStart * (dist / _pinchDist0));
                  } else if (_activePointers.length == 1 && prev != null && !_draggingHandle &&
                      // La pulsación larga ya creó una selección con este
                      // dedo: lo usa xterm para extenderla, aquí no se scrollea.
                      (identical(_selAtDown[e.pointer], _terminalController.selection) ||
                       _terminalController.selection == null)) {
                    final origin = _dragOrigin[e.pointer]!;
                    final dy = (e.localPosition.dy - origin.dy).abs();
                    final dx = (e.localPosition.dx - origin.dx).abs();
                    if (!_isDragging.contains(e.pointer) &&
                        dy > _kScrollSlop && dy > dx) {
                      _isDragging.add(e.pointer);
                    }
                    _vTracker?.addPosition(e.timeStamp, e.localPosition);
                    if (_isDragging.contains(e.pointer)) {
                      _applyScrollDelta(
                          e.localPosition.dy - prev.dy, e.localPosition);
                    }
                  }
                },
                onPointerUp: (e) {
                  final wasTap = !_isDragging.contains(e.pointer) &&
                      !_draggingHandle &&
                      _activePointers.length == 1 &&
                      _terminalController.selection == null;
                  final wasScrollDrag = _isDragging.contains(e.pointer) &&
                      !_draggingHandle &&
                      (identical(_selAtDown[e.pointer],
                              _terminalController.selection) ||
                          _terminalController.selection == null);
                  _activePointers.remove(e.pointer);
                  _dragOrigin.remove(e.pointer);
                  _isDragging.remove(e.pointer);
                  _selAtDown.remove(e.pointer);
                  if (_activePointers.isEmpty) {
                    _altScrollAccum = 0;
                    if (wasScrollDrag && !_arrowsLock) {
                      final v =
                          _vTracker?.getVelocity().pixelsPerSecond.dy ?? 0;
                      if (v.abs() > 240) _startFling(v, e.localPosition);
                    }
                    _vTracker = null;
                  }
                  if (wasTap) _maybeOpenUrl(e.localPosition);
                },
                onPointerCancel: (e) {
                  _activePointers.remove(e.pointer);
                  _dragOrigin.remove(e.pointer);
                  _isDragging.remove(e.pointer);
                  _selAtDown.remove(e.pointer);
                  if (_activePointers.isEmpty) {
                    _altScrollAccum = 0;
                    _vTracker = null;
                  }
                },
                child: termView,
              ),

              // Handles de selección + botón copiar
              ListenableBuilder(
                listenable: _terminalController,
                builder: (_, __) {
                  final sel = _terminalController.selection;
                  if (sel == null) return const SizedBox.shrink();

                  Offset? startPx;
                  Offset? endPx;
                  double lineH = _fontSize * 1.4;
                  double cellW = _fontSize * 0.6;
                  try {
                    final r = _terminalViewKey.currentState!.renderTerminal;
                    lineH  = r.lineHeight;
                    cellW  = r.cellSize.width;
                    startPx = r.getOffset(sel.begin);
                    endPx   = r.getOffset(sel.end);
                  } catch (_) {}

                  return Stack(children: [
                    if (startPx != null)
                      _buildHandle(
                        center: Offset(startPx.dx, startPx.dy + lineH),
                        isEnd: false,
                        anchorPx: endPx != null
                            ? Offset(endPx.dx + cellW / 2, endPx.dy + lineH / 2)
                            : null,
                      ),
                    if (endPx != null)
                      _buildHandle(
                        center: Offset(endPx.dx + cellW, endPx.dy + lineH),
                        isEnd: true,
                        anchorPx: startPx != null
                            ? Offset(startPx.dx + cellW / 2, startPx.dy + lineH / 2)
                            : null,
                      ),
                    Positioned(
                      top: 8, right: 8,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        GestureDetector(
                          onTap: _copySelectionJoined,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: kAccent2.withOpacity(0.92),
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: const [
                                BoxShadow(
                                    color: Colors.black38, blurRadius: 6)
                              ],
                            ),
                            child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.wrap_text,
                                      size: 15, color: Colors.black),
                                  const SizedBox(width: 6),
                                  Text(tr('1 line'),
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black)),
                                ]),
                          ),
                        ),
                        GestureDetector(
                          onTap: _copySelection,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: kAccent.withOpacity(0.92),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.copy, size: 15, color: Colors.black),
                            const SizedBox(width: 6),
                            Text(tr('Copy'), style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600,
                                color: Colors.black)),
                          ]),
                        ),
                        ),
                      ]),
                    ),
                  ]);
                },
              ),

              // Overlay de sesión cerrada
              if (!_connected && !_isLocal)
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xEE0A0E1A),
                      border: Border(top: BorderSide(color: kError.withOpacity(0.5))),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        const Icon(Icons.link_off, color: kError, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _status,
                            style: const TextStyle(color: kTextSec, fontSize: 13),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: reconnect,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: Text(tr('Reconnect')),
                          style: TextButton.styleFrom(
                            foregroundColor: kAccent,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            textStyle: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Overlay de modo flechas
              if (_arrowsLock)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: (_) {
                      _swipeX = 0; _swipeY = 0; _scaleStart = _fontSize;
                    },
                    onScaleUpdate: (d) {
                      if (d.pointerCount >= 2) {
                        _setFontSize(_scaleStart * d.scale);
                      } else {
                        _swipeX += d.focalPointDelta.dx;
                        _swipeY += d.focalPointDelta.dy;
                        while (_swipeX.abs() >= _kSwipeStep &&
                               _swipeX.abs() >= _swipeY.abs()) {
                          _sendRaw(_swipeX > 0 ? _kRight : _kLeft);
                          _swipeX += _swipeX > 0 ? -_kSwipeStep : _kSwipeStep;
                        }
                        while (_swipeY.abs() >= _kSwipeStep &&
                               _swipeY.abs() >= _swipeX.abs()) {
                          _sendRaw(_swipeY > 0 ? _kDown : _kUp);
                          _swipeY += _swipeY > 0 ? -_kSwipeStep : _kSwipeStep;
                        }
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
        RepaintBoundary(child: _buildKeyboard()),
      ],
    );
  }

  // Círculo arrastrable para extender la selección de texto
  Widget _buildHandle({
    required Offset center,
    required bool isEnd,
    required Offset? anchorPx,
  }) {
    const r = 11.0;
    return Positioned(
      left: center.dx - r,
      top:  center.dy - r,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) {
          _stopFling();
          _selAnchorPx = anchorPx;
          setState(() => _draggingHandle = true);
        },
        onPanUpdate: (d) {
          final anchor = _selAnchorPx;
          if (anchor == null) return;
          // Convertir posición global del dedo a coords del TerminalView
          final box = _terminalViewKey.currentContext?.findRenderObject();
          if (box is! RenderBox) return;
          final fingerPos = box.globalToLocal(d.globalPosition);
          if (isEnd) _updateAutoScroll(fingerPos, box.size);
          if (_autoScrollTimer != null) return; // el tick extiende la selección
          try {
            final render = _terminalViewKey.currentState!.renderTerminal;
            if (isEnd) {
              render.selectCharacters(anchor, fingerPos);
            } else {
              render.selectCharacters(fingerPos, anchor);
            }
          } catch (_) {}
        },
        onPanEnd: (_) {
          _stopAutoScroll();
          setState(() { _draggingHandle = false; _selAnchorPx = null; });
        },
        onPanCancel: () {
          _stopAutoScroll();
          setState(() { _draggingHandle = false; _selAnchorPx = null; });
        },
        child: Container(
          width: r * 2,
          height: r * 2,
          decoration: const BoxDecoration(
            color: kAccent,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 4)],
          ),
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (!widget.showAppBar) return _buildBody();

    return Scaffold(
      backgroundColor: TermThemes.current.background,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: kSurface,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              width: 8, height: 8,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _connected ? kSuccess : kError,
              ),
            ),
            Expanded(
              child: Text(_status,
                  style: const TextStyle(fontSize: 14, color: kTextPri),
                  overflow: TextOverflow.ellipsis),
            ),
            if (_arrowsLock)
              Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD93D).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFFFFD93D).withOpacity(0.5)),
                ),
                child: Text(tr('⇅↔'),
                    style: TextStyle(fontSize: 11, color: Color(0xFFFFD93D))),
              ),
          ],
        ),
        actions: [
          if (!_connected)
            IconButton(
              icon: const Icon(Icons.refresh, size: 20, color: kTextSec),
              onPressed: _connect,
            ),
          IconButton(
            icon: const Icon(Icons.text_decrease, size: 18, color: kTextSec),
            onPressed: () {
              _setFontSize(_fontSize - 1);
              _refocus();
            },
          ),
          IconButton(
            icon: const Icon(Icons.text_increase, size: 18, color: kTextSec),
            onPressed: () {
              _setFontSize(_fontSize + 1);
              _refocus();
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _buildBody(),
      ),
    );
  }
}
