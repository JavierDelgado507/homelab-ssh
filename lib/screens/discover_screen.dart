import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../main.dart';
import '../models/host.dart';
import '../services/i18n.dart';
import '../services/storage_service.dart';

/// Descubre dispositivos con SSH en la red local: escanea el /24 de la IP
/// del móvil buscando el puerto 22 abierto. Devuelve (pop) la IP elegida.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final List<String> _found = [];
  Map<String, Host> _known = {}; // ip → host guardado
  bool _scanning = false;
  int _done = 0;
  String? _base; // "192.168.1"
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  Future<String?> _localBase() async {
    try {
      final ifaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLinkLocal: false);
      for (final i in ifaces) {
        for (final a in i.addresses) {
          if (a.isLoopback) continue;
          final parts = a.address.split('.');
          if (parts.length != 4) continue;
          // redes privadas típicas
          if (parts[0] == '10' ||
              parts[0] == '192' && parts[1] == '168' ||
              parts[0] == '172') {
            return parts.sublist(0, 3).join('.');
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<bool> _probe(String ip) async {
    try {
      final s = await Socket.connect(ip, 22,
          timeout: const Duration(milliseconds: 600));
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _found.clear();
      _done = 0;
    });
    final hosts = await StorageService.getHosts();
    _known = {for (final h in hosts) h.hostname: h};

    final base = await _localBase();
    if (base == null) {
      if (mounted) {
        setState(() => _scanning = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr('Could not determine the local network (no Wi-Fi?)'))));
      }
      return;
    }
    _base = base;

    final ips = [for (var i = 1; i <= 254; i++) '$base.$i'];
    const chunk = 32;
    for (var i = 0; i < ips.length; i += chunk) {
      if (_cancelled || !mounted) return;
      final batch = ips.sublist(
          i, i + chunk > ips.length ? ips.length : i + chunk);
      final results = await Future.wait(batch.map(_probe));
      if (_cancelled || !mounted) return;
      setState(() {
        for (var j = 0; j < batch.length; j++) {
          if (results[j]) _found.add(batch[j]);
        }
        _found.sort((a, b) => int.parse(a.split('.').last)
            .compareTo(int.parse(b.split('.').last)));
        _done += batch.length;
      });
    }
    if (mounted) setState(() => _scanning = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Discover local devices'), style: TextStyle(fontSize: 16)),
            Text(
              _scanning
                  ? '${Tr.es ? 'Buscando SSH en' : 'Scanning'} ${_base ?? '…'}.0/24  ($_done/254)'
                  : '${_found.length} ${Tr.es ? 'dispositivos con SSH' : 'devices with SSH'}',
              style: const TextStyle(fontSize: 11, color: kTextSec),
            ),
          ],
        ),
        actions: [
          if (_scanning)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: kAccent),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh, color: kTextSec),
              onPressed: _scan,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: _found.isEmpty && !_scanning
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.wifi_find_outlined,
                      size: 56, color: kTextSec.withOpacity(0.4)),
                  const SizedBox(height: 16),
                  Text(tr('Nothing with SSH in sight'),
                      style: TextStyle(color: kTextSec, fontSize: 16)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              itemCount: _found.length,
              itemBuilder: (_, i) {
                final ip = _found[i];
                final known = _known[ip];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: kCard,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.pop(context, ip),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            Icon(
                              known != null
                                  ? Icons.dns
                                  : Icons.device_unknown_outlined,
                              size: 20,
                              color: known != null ? kAccent : kTextSec,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(ip,
                                      style: const TextStyle(
                                          color: kTextPri,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600)),
                                  if (known != null)
                                    Text('${Tr.es ? 'Guardado como' : 'Saved as'} "${known.name}"',
                                        style: const TextStyle(
                                            color: kAccent, fontSize: 12)),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right,
                                color: kTextSec, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
