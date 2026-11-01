import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'screens/hosts_screen.dart';
import 'screens/keys_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/snippets_screen.dart';
import 'screens/terminal_tabs_screen.dart';
import 'services/i18n.dart';
import 'services/ssh_keepalive_service.dart';
import 'services/storage_service.dart';

// Paleta Termius
const kBg        = Color(0xFF0A0E1A);
const kSurface   = Color(0xFF141929);
const kCard      = Color(0xFF1C2340);
const kCardHover = Color(0xFF232B4A);
const kAccent    = Color(0xFF4ECDC4);
const kAccent2   = Color(0xFF5B8AF5);
const kTextPri   = Color(0xFFE8EAF0);
const kTextSec   = Color(0xFF8892B0);
const kDivider   = Color(0xFF252D4A);
const kError     = Color(0xFFFF6B6B);
const kSuccess   = Color(0xFF4ECDC4);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  // JetBrains Mono se distribuye bajo la SIL Open Font License
  LicenseRegistry.addLicense(() async* {
    final ofl = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(['JetBrains Mono'], ofl);
  });
  await Tr.load();
  SshKeepaliveService.init();
  runApp(const HomelabSshApp());
}

class HomelabSshApp extends StatelessWidget {
  const HomelabSshApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: Tr.notifier,
      builder: (_, lang, __) => MaterialApp(
      key: ValueKey(lang),
      title: 'Homelab SSH',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        colorScheme: const ColorScheme.dark(
          primary: kAccent,
          secondary: kAccent2,
          surface: kSurface,
          error: kError,
          onPrimary: Colors.black,
          onSurface: kTextPri,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: kSurface,
          foregroundColor: kTextPri,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: kTextPri,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          iconTheme: IconThemeData(color: kTextSec),
        ),
        cardTheme: const CardTheme(
          color: kCard,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: kCard,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: kDivider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: kDivider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: kAccent, width: 1.5),
          ),
          labelStyle: const TextStyle(color: kTextSec),
          hintStyle: const TextStyle(color: kTextSec),
        ),
        dividerColor: kDivider,
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: kAccent,
          foregroundColor: Colors.black,
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: kTextPri),
          bodyMedium: TextStyle(color: kTextPri),
          bodySmall: TextStyle(color: kTextSec),
          titleMedium: TextStyle(color: kTextPri, fontWeight: FontWeight.w600),
        ),
        segmentedButtonTheme: const SegmentedButtonThemeData(
          style: ButtonStyle(
            backgroundColor: WidgetStatePropertyAll(kCard),
          ),
        ),
      ),
      home: const AppLockGate(child: RootScreen()),
      ),
    );
  }
}

/// Bloqueo biométrico opcional: si está activado (menú ⋮ de Keychain), pide
/// huella/PIN al abrir en frío y al volver tras >5 min en segundo plano.
class AppLockGate extends StatefulWidget {
  final Widget child;
  const AppLockGate({super.key, required this.child});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate>
    with WidgetsBindingObserver {
  bool _locked = false;
  bool _checking = true;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    StorageService.getAppLock().then((enabled) {
      if (!mounted) return;
      setState(() { _locked = enabled; _checking = false; });
      if (enabled) _authenticate();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed && !_locked) {
      final away = _pausedAt == null
          ? Duration.zero
          : DateTime.now().difference(_pausedAt!);
      if (away > const Duration(minutes: 5)) {
        StorageService.getAppLock().then((enabled) {
          if (enabled && mounted) {
            setState(() => _locked = true);
            _authenticate();
          }
        });
      }
    }
  }

  Future<void> _authenticate() async {
    try {
      final ok = await LocalAuthentication().authenticate(
        localizedReason: tr('Unlock Homelab SSH'),
        options: const AuthenticationOptions(stickyAuth: true),
      );
      if (ok && mounted) setState(() => _locked = false);
    } catch (_) {
      // Sin biometría disponible (p. ej. tras un restore): no dejar fuera
      if (mounted) setState(() => _locked = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(backgroundColor: kBg, body: SizedBox());
    }
    if (!_locked) return widget.child;
    return Scaffold(
      backgroundColor: kBg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 56, color: kAccent),
            const SizedBox(height: 16),
            Text(tr('Homelab SSH is locked'),
                style: TextStyle(color: kTextPri, fontSize: 17)),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: kAccent, foregroundColor: Colors.black),
              onPressed: _authenticate,
              icon: const Icon(Icons.fingerprint),
              label: Text(tr('Unlock')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Raíz: mantiene montados el menú y los terminales a la vez (IndexedStack),
/// así volver al menú no destruye las sesiones SSH.
class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  final _hub = TabsHub.instance;

  @override
  void initState() {
    super.initState();
    _hub.addListener(_update);
  }

  @override
  void dispose() {
    _hub.removeListener(_update);
    super.dispose();
  }

  void _update() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Atrás de Android en los terminales → menú (las sesiones siguen vivas)
      canPop: !_hub.showing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _hub.goHome();
      },
      child: IndexedStack(
        index: _hub.showing ? 1 : 0,
        children: const [HomeShell(), TerminalTabsScreen()],
      ),
    );
  }
}

/// Pestaña activa del menú inicial; otras pantallas pueden pedir un cambio
/// (p. ej. volver a Hosts tras importar una copia).
final ValueNotifier<int> kHomeTab = ValueNotifier(0);

/// Aviso global de «los datos han cambiado» (tras importar una copia): las
/// pestañas que cachean listas se recargan al oírlo.
final ValueNotifier<int> kDataChanged = ValueNotifier(0);

/// Menú inicial estilo Termius: secciones con barra inferior.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int get _index => kHomeTab.value;

  @override
  void initState() {
    super.initState();
    kHomeTab.addListener(_onTab);
  }

  @override
  void dispose() {
    kHomeTab.removeListener(_onTab);
    super.dispose();
  }

  void _onTab() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: IndexedStack(
        index: _index,
        children: const [
          HostsScreen(),
          SnippetsScreen(),
          KeysScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: kSurface,
          indicatorColor: kAccent.withOpacity(0.18),
          height: 64,
          labelTextStyle: WidgetStatePropertyAll(
            const TextStyle(fontSize: 11, color: kTextSec),
          ),
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              size: 22,
              color: states.contains(WidgetState.selected)
                  ? kAccent
                  : kTextSec,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => kHomeTab.value = i,
          destinations: [
            const NavigationDestination(
                icon: Icon(Icons.dns_outlined), label: 'Hosts'),
            const NavigationDestination(
                icon: Icon(Icons.code), label: 'Snippets'),
            NavigationDestination(
                icon: const Icon(Icons.vpn_key_outlined), label: tr('Keys')),
            NavigationDestination(
                icon: const Icon(Icons.settings_outlined),
                label: tr('Settings')),
          ],
        ),
      ),
    );
  }
}
