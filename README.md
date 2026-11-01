# Homelab SSH

An Android SSH client built for homelabs. Born because the author wanted a
Termius-style client that was fully his: no accounts, no cloud, no paywall —
everything stays on your device.

![Flutter](https://img.shields.io/badge/Flutter-3.24-blue) ![License](https://img.shields.io/badge/license-MIT-green)

## Features

**Terminal**
- Fast terminal based on a heavily patched fork of [xterm.dart](https://pub.dev/packages/xterm)
  (paragraph-cache leaks fixed, private CSI sequences handled, OSC 52 clipboard,
  batched SSH output, smooth kinetic scrolling) — works great with TUI apps,
  including AI coding CLIs.
- Multiple tabs; sessions survive navigating back home (foreground service
  keeps them alive in the background).
- Extra key bar (Esc/Ctrl/Alt/Shift, arrows, Fn, symbols), pinch-to-zoom,
  text selection with draggable handles, cumulative screen copy.
- Command autocomplete: learns the commands you run and suggests completions
  as you type (local history only, never leaves the device).

**Connections**
- Quick connect: type `root@192.168.1.99` or `ssh user@host -p 2222` in the
  search bar and hit connect — no need to save the host.
- Discover local devices: scans your /24 for machines listening on SSH.
- ProxyJump: connect through one of your saved hosts (chains supported).
- Automatic reconnection with backoff; connect timeout; per-host startup
  command; optional persistent sessions via tmux (`tmux new -A`) so you
  resume exactly where you left off.
- Jump tracking: if you `ssh` onward (or `pct enter` an LXC on a Proxmox
  host) inside the terminal, the SFTP button offers the place you are *now* —
  for LXC containers the IP is resolved through the existing connection.

**Security**
- Host key verification (trust on first use) with a clear warning when a
  fingerprint changes; fingerprint manager in Settings.
- Password and key auth; encrypted (passphrase-protected) keys supported;
  generate ed25519 keys in-app.
- Everything (hosts, passwords, keys, snippets) stored in Android's
  EncryptedSharedPreferences. Optional biometric app lock.
- Encrypted backups: export/import everything as a single AES-256-GCM file
  (PBKDF2, 150k iterations).

**Files**
- SFTP browser per host or from any terminal: streaming uploads/downloads
  with progress (large files welcome), rename/delete/mkdir, save downloads
  anywhere via the system file picker.

**Little things**
- Host groups with filter chips, drag to reorder, duplicate host.
- Launcher shortcuts (long-press the app icon) for your top hosts.
- Local device shell. Snippets with defaults for common server tasks.

## Install

Grab the APK from [Releases](../../releases) and install it. Android 8.0+.

## Build

```bash
flutter pub get
flutter build apk --release
```

To sign a release, create `android/key.properties` pointing at your own
keystore (see `android/app/build.gradle`); without it the build falls back
to the debug signature.

## Privacy

There is no telemetry, no analytics and no network traffic other than the
SSH/SFTP connections you open. Credentials never leave your device except
inside the encrypted backups you export yourself.

## License

MIT — see [LICENSE](LICENSE). The bundled terminal is a fork of
[xterm.dart](https://pub.dev/packages/xterm) (MIT, © 2020 xuty), kept under
`packages/xterm` with its original license. The JetBrains Mono font is
distributed under the SIL Open Font License 1.1.
