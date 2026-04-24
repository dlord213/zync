import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:multicast_dns/multicast_dns.dart';

/// Resolves the device's LAN/WiFi IPv4 address.
/// Falls back to '127.0.0.1' if none is found.
Future<String> getLocalIp() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );
    for (final iface in interfaces) {
      // Prefer wlan / en interfaces (WiFi) over loopback
      final name = iface.name.toLowerCase();
      if (name.contains('wlan') ||
          name.contains('en') ||
          name.contains('eth') ||
          name.contains('wlp') ||
          name.contains('eno')) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    }
    // Fallback: return the first non-loopback address found
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback) return addr.address;
      }
    }
  } catch (_) {}
  return '127.0.0.1';
}

// Service type Zync advertises and listens for
const _kServiceType = '_zync._tcp.local';

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
      other is DiscoveredDevice && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);
}

class P2PService {
  HttpServer? _server;
  bool _mdnsStarted = false;

  late final MDnsClient _mdns = MDnsClient(
    rawDatagramSocketFactory:
        (dynamic host, int port,
            {bool? reuseAddress, bool? reusePort, int? ttl}) {
      return RawDatagramSocket.bind(
        host,
        port,
        reuseAddress: true,
        reusePort:
            Platform.isAndroid || Platform.isLinux || Platform.isWindows
                ? false
                : (reusePort ?? true),
        ttl: ttl ?? 255,
      );
    },
  );

  // ── Server ──────────────────────────────────────────────────────────────────

  /// Starts a local HTTP server that serves [file], and returns the real
  /// local IP address so it can be encoded in the QR code.
  Future<String> startServerAndBroadcast(File file) async {
    print('Starting server for file: ${file.path}');

    // Resolve the true local IP before binding
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
      // Close any previous server first
      await _server?.close(force: true);
      _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, 8080);
      print('Serving at http://$localIp:${_server!.port}');

      if (!_mdnsStarted) {
        await _mdns.start();
        _mdnsStarted = true;
      }
      print('mDNS broadcast started');
    } catch (e) {
      print('Error starting server: $e');
    }

    return localIp;
  }

  // ── Discovery stream ────────────────────────────────────────────────────────

  /// Returns a [Stream] of [DiscoveredDevice]s found on the local network
  /// via mDNS (service type: [_kServiceType]).
  ///
  /// The stream stays open until [stop] is called. Duplicates are filtered
  /// so the same host:port pair is only emitted once.
  Stream<DiscoveredDevice> discoverDevices() {
    final controller = StreamController<DiscoveredDevice>.broadcast();
    final seen = <String>{};

    Future<void> _run() async {
      print('Discovering devices via mDNS ($_kServiceType)…');
      try {
        if (!_mdnsStarted) {
          await _mdns.start();
          _mdnsStarted = true;
        }

        // Step 1 – PTR records  →  service instances
        await for (final PtrResourceRecord ptr
            in _mdns.lookup<PtrResourceRecord>(
          ResourceRecordQuery.serverPointer(_kServiceType),
        )) {
          print('PTR record: ${ptr.domainName}');

          // Step 2 – SRV records  →  host + port for each instance
          await for (final SrvResourceRecord srv
              in _mdns.lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(ptr.domainName),
          )) {
            print('SRV record: ${srv.target}:${srv.port}');

            // Step 3 – A record  →  IP address
            String ip = srv.target;
            await for (final IPAddressResourceRecord addr
                in _mdns.lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv4(srv.target),
            )) {
              ip = addr.address.address;
              print('IP resolved: $ip');
              break; // first result is fine
            }

            final key = '${srv.target}:${srv.port}';
            if (!seen.contains(key) && !controller.isClosed) {
              seen.add(key);
              // Derive a readable name: the part before the first '.' is the
              // instance name that the sender advertised.
              final name =
                  ptr.domainName.split('.').first.replaceAll('-', ' ');

              controller.add(DiscoveredDevice(
                name: name.isNotEmpty ? name : srv.target,
                host: srv.target,
                port: srv.port,
                ip: ip,
              ));
            }
          }
        }
      } catch (e) {
        print('mDNS discovery error: $e');
      }
    }

    _run();
    return controller.stream;
  }

  // ── Cleanup ─────────────────────────────────────────────────────────────────

  void stop() {
    _server?.close();
    if (_mdnsStarted) {
      _mdns.stop();
      _mdnsStarted = false;
    }
  }
}
