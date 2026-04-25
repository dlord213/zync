import 'dart:async';
import 'dart:io';
import 'package:bonsoir/bonsoir.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

// Zync's mDNS service type (bonsoir format, no .local suffix)
const _kServiceType = '_zync._tcp';

/// Resolves the device's LAN/WiFi IPv4 address.
/// Falls back to '127.0.0.1' if none is found.
Future<String> getLocalIp() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );
    
    // Filter out common virtual/tunnel adapters
    final validInterfaces = interfaces.where((iface) {
      final name = iface.name.toLowerCase();
      return !name.contains('docker') &&
             !name.contains('vbox') &&
             !name.contains('vmware') &&
             !name.contains('virtual') &&
             !name.contains('tailscale') &&
             !name.contains('zerotier') &&
             !name.contains('tun') &&
             !name.contains('tap') &&
             !name.contains('wg');
    }).toList();

    // Prefer WiFi/Ethernet interfaces
    for (final iface in validInterfaces) {
      final name = iface.name.toLowerCase();
      if (name.contains('wlan') ||
          name.contains('wi-fi') || // Windows
          name.contains('wifi') ||
          name.contains('en') ||
          name.contains('eth') ||
          name.contains('wlp') ||
          name.contains('eno')) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.address.startsWith(RegExp(r'^(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)'))) {
             return addr.address;
          }
        }
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    }
    
    // Fallback: return the first valid non-loopback address found
    for (final iface in validInterfaces) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback) return addr.address;
      }
    }
  } catch (_) {}
  return '127.0.0.1';
}

class DiscoveredDevice {
  final String name;
  final String host;
  final int port;
  final String ip;

  const DiscoveredDevice({
    required this.name,
    required this.host,
    required this.port,
    required this.ip,
  });

  @override
  bool operator ==(Object other) =>
      other is DiscoveredDevice && other.ip == ip && other.port == port;

  @override
  int get hashCode => Object.hash(ip, port);
}

class P2PService {
  HttpServer? _server;
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;

  // ── Server + advertisement ──────────────────────────────────────────────────

  /// Starts a local HTTP server that serves [file], registers it on the local
  /// network via mDNS (bonsoir), and returns the real local IP address.
  Future<String> startServerAndBroadcast(File file) async {
    print('Starting server for file: ${file.path}');

    final localIp = await getLocalIp();
    print('Local IP: $localIp');

    final fileName = file.path.split(Platform.pathSeparator).last;

    final handler = const Pipeline().addHandler((Request request) async {
      final bytes = await file.readAsBytes();
      return Response.ok(
        bytes,
        headers: {
          'Content-Type': 'application/octet-stream',
          'Content-Disposition': 'attachment; filename="$fileName"',
          'Content-Length': '${bytes.length}',
        },
      );
    });

    try {
      // Restart server cleanly
      await _server?.close(force: true);
      _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, 8080);
      print('Serving at http://$localIp:${_server!.port}');

      // Advertise via bonsoir so receivers can discover us via mDNS
      await _broadcast?.stop();
      final service = BonsoirService(
        name: 'Zync-${localIp.replaceAll('.', '-')}',
        type: _kServiceType,
        port: _server!.port,
      );
      _broadcast = BonsoirBroadcast(service: service);
      await _broadcast!.ready;
      await _broadcast!.start();
      print('mDNS advertisement started as: ${service.name}');
    } catch (e) {
      print('Error starting server: $e');
    }

    return localIp;
  }

  // ── Discovery ───────────────────────────────────────────────────────────────

  /// Returns a [Stream] of [DiscoveredDevice]s found via mDNS on the local
  /// network. Deduplicates by ip:port. The stream stays open until [stop].
  Stream<DiscoveredDevice> discoverDevices() {
    final controller = StreamController<DiscoveredDevice>.broadcast();
    final seen = <String>{};

    Future<void> _run() async {
      print('Starting mDNS discovery for $_kServiceType …');
      try {
        _discovery = BonsoirDiscovery(type: _kServiceType);
        await _discovery!.ready;

        _discovery!.eventStream?.listen((BonsoirDiscoveryEvent event) {
          if (event.type == BonsoirDiscoveryEventType.discoveryServiceFound) {
            print('Found service (resolving): ${event.service?.name}');
            event.service?.resolve(_discovery!.serviceResolver!);
          } else if (event.type ==
              BonsoirDiscoveryEventType.discoveryServiceResolved) {
            final svc = event.service as ResolvedBonsoirService?;
            if (svc == null) return;

            final ip = svc.host ?? '';
            final key = '$ip:${svc.port}';
            if (ip.isEmpty || seen.contains(key) || controller.isClosed) {
              return;
            }
            seen.add(key);
            print('Resolved device: ${svc.name} @ $ip:${svc.port}');
            controller.add(DiscoveredDevice(
              name: svc.name,
              host: ip,
              port: svc.port,
              ip: ip,
            ));
          } else if (event.type ==
              BonsoirDiscoveryEventType.discoveryServiceLost) {
            print('Lost service: ${event.service?.name}');
          }
        });

        await _discovery!.start();
      } catch (e) {
        print('mDNS discovery error: $e');
        if (!controller.isClosed) controller.addError(e);
      }
    }

    _run();
    return controller.stream;
  }

  // ── Cleanup ─────────────────────────────────────────────────────────────────

  Future<void> stop() async {
    await _server?.close(force: true);
    await _broadcast?.stop();
    await _discovery?.stop();
    _server = null;
    _broadcast = null;
    _discovery = null;
  }
}
