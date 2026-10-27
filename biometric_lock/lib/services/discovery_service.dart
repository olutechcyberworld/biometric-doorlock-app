import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class DiscoveredDevice {
  final String id;
  final String ip;
  final int port;

  DiscoveredDevice({required this.id, required this.ip, this.port = 80});
}

/// Finds the lock on the local network without the owner typing an IP (the IP is whatever the network hands out).
///
/// Two independent methods run in parallel, first hit wins:
///  1. UDP beacon: the lock broadcasts {"t":"doorlock","id","ip","port"} to UDP 4210 every ~3 s while online.
///  2. Subnet probe: GET /whoami on every host of the phone's own /24 (works even when broadcasts are filtered).
/// mDNS is deliberately NOT used: on an Android phone that is itself the hotspot it usually does not work.
class DiscoveryService {
  static const int beaconPort = 4210;
  static final RegExp _lanIface = RegExp(r'^(wlan|swlan|ap|softap|eth)');

  static Future<DiscoveredDevice?> discover(
      {Duration timeout = const Duration(seconds: 8)}) async {
    final completer = Completer<DiscoveredDevice?>();
    RawDatagramSocket? sock;

    void found(DiscoveredDevice d) {
      if (!completer.isCompleted) completer.complete(d);
    }

    try {
      sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, beaconPort,
          reuseAddress: true);
      sock.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = sock?.receive();
        if (dg == null) return;
        try {
          final m = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
          final ip = m['ip'] as String?;
          if (m['t'] == 'doorlock' && ip != null && ip.isNotEmpty) {
            found(DiscoveredDevice(
              id: (m['id'] as String?) ?? '',
              ip: ip,
              port: (m['port'] as num?)?.toInt() ?? 80,
            ));
          }
        } catch (_) {}
      });
    } catch (_) {
      // Port busy or sockets blocked: the subnet probe below still works.
    }

    unawaited(_sweep(found, () => completer.isCompleted));

    final timer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(null);
    });
    final result = await completer.future;
    timer.cancel();
    sock?.close();
    return result;
  }

  static Future<void> _sweep(
      void Function(DiscoveredDevice) onFound, bool Function() isDone) async {
    final prefixes = <String>{};
    try {
      for (final iface
          in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        if (!_lanIface.hasMatch(iface.name)) continue; // skip mobile-data / VPN interfaces
        for (final a in iface.addresses) {
          final p = a.address.split('.');
          if (p.length == 4 && !a.isLoopback) {
            prefixes.add('${p[0]}.${p[1]}.${p[2]}');
          }
        }
      }
    } catch (_) {
      return;
    }
    for (final prefix in prefixes) {
      for (var start = 1; start <= 254 && !isDone(); start += 32) {
        final batch = <Future<void>>[];
        for (var h = start; h < start + 32 && h <= 254; h++) {
          batch.add(_probe('$prefix.$h', onFound));
        }
        await Future.wait(batch);
      }
      if (isDone()) return;
    }
  }

  static Future<void> _probe(
      String ip, void Function(DiscoveredDevice) onFound) async {
    try {
      final res = await http
          .get(Uri.parse('http://$ip/whoami'))
          .timeout(const Duration(milliseconds: 700));
      if (res.statusCode != 200) return;
      final m = jsonDecode(res.body) as Map<String, dynamic>;
      if (m['device'] == 'doorlock') {
        onFound(DiscoveredDevice(id: (m['id'] as String?) ?? '', ip: ip));
      }
    } catch (_) {}
  }
}
