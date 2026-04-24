import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:multicast_dns/multicast_dns.dart';

class P2PService {
  HttpServer? _server;
  late final MDnsClient _mdns = MDnsClient(
    rawDatagramSocketFactory: (dynamic host, int port, {bool? reuseAddress, bool? reusePort, int? ttl}) {
      return RawDatagramSocket.bind(
        host,
        port,
        reuseAddress: true,
        reusePort: Platform.isAndroid || Platform.isLinux || Platform.isWindows ? false : (reusePort ?? true),
        ttl: ttl ?? 255,
      );
    },
  );

  /// Starts a local HTTP server and broadcasts its presence via mDNS.
  Future<void> startServerAndBroadcast(File file) async {
    print("Starting server for file: ${file.path}");
    
    // Placeholder shelf handler
    var handler = const Pipeline().addHandler((Request request) {
      return Response.ok('File sharing server running.');
    });

    try {
      _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, 8080);
      print('Serving at http://${_server!.address.host}:${_server!.port}');
      
      // Placeholder mDNS broadcast
      await _mdns.start();
      print("mDNS broadcast started");
      
    } catch (e) {
      print("Error starting server: $e");
    }
  }

  /// Listens for mDNS broadcasts from other devices.
  Future<void> discoverDevices() async {
    print("Discovering devices via mDNS...");
    
    try {
      await _mdns.start();
      // Placeholder: listen for specific mDNS service type
      // await for (final PtrResourceRecord ptr in _mdns.lookup<PtrResourceRecord>(
      //     ResourceRecordQuery.serverPointer('_http._tcp.local'))) {
      //   print("Found device: ${ptr.domainName}");
      // }
      print("mDNS listening started");
    } catch (e) {
      print("Error discovering devices: $e");
    }
  }

  void stop() {
    _server?.close();
    _mdns.stop();
  }
}
