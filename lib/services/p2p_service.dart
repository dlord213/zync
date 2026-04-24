import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:multicast_dns/multicast_dns.dart';

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

  /// Starts a local HTTP server and broadcasts its presence via mDNS.
  Future<void> startServerAndBroadcast(File file) async {
    print('Starting server for file: ${file.path}');

    final handler = const Pipeline().addHandler((Request request) {
      return Response.ok('File sharing server running.');
    });

    try {
      _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, 8080);
      print('Serving at http://${_server!.address.host}:${_server!.port}');

      if (!_mdnsStarted) {
        await _mdns.start();
        _mdnsStarted = true;
      }
      print('mDNS broadcast started');
    } catch (e) {
      print('Error starting server: $e');
    }
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
