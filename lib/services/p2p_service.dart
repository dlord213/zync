import 'dart:async';
import 'dart:io';
import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';

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
    
    // Filter out common virtual/tunnel/bridge adapters
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
             !name.contains('wg') &&
             !name.contains('veth') &&
             !name.contains('br-') &&
             !name.contains('bridge') &&
             !name.contains('dummy') &&
             !name.contains('ifb');
    }).toList();

    // 1. Prefer Wi-Fi interfaces
    for (final iface in validInterfaces) {
      final name = iface.name.toLowerCase();
      if (name.contains('wlan') ||
          name.contains('wi-fi') ||
          name.contains('wifi') ||
          name.contains('wlp')) {
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

    // 2. Fallback to Ethernet interfaces
    for (final iface in validInterfaces) {
      final name = iface.name.toLowerCase();
      if (name.contains('en') ||
          name.contains('eth') ||
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
    
    // 3. Fallback: return the first valid non-loopback address found
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
  static const _channel = MethodChannel('com.mirimomekiku.zync/system_settings');

  HttpServer? _server;
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;

  /// Attempts to open the mobile hotspot settings page on Android.
  Future<bool> openHotspotSettings() async {
    if (Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod<bool>('openHotspotSettings');
        return result ?? false;
      } catch (e) {
        print('Error launching hotspot settings: $e');
        return false;
      }
    }
    return false;
  }

  // ── Server + advertisement ──────────────────────────────────────────────────

  /// Starts a local HTTP server that serves [entity], registers it on the local
  /// network via mDNS (bonsoir), and returns the real local IP address.
  Future<String> startServerAndBroadcast(dynamic entity, {VoidCallback? onFileRequested}) async {
    print('Starting server for: ${entity is List ? 'Multiple Files' : (entity as FileSystemEntity).path}');

    final localIp = await getLocalIp();
    print('Local IP: $localIp');

    String fileName = 'SharedFiles.zync';
    List<int> bytes;

    if (entity is Directory) {
      // It's a folder, zip it
      fileName = '${p.basename(entity.path)}.zync';
      bytes = await _archiveDirectory(entity);
    } else if (entity is File) {
      fileName = p.basename(entity.path);
      bytes = await entity.readAsBytes();
    } else if (entity is List<File>) {
      fileName = 'Files.zync';
      bytes = await _archiveFiles(entity);
    } else {
      throw Exception('Unsupported entity type');
    }

    final handler = const Pipeline().addHandler((Request request) async {
      if (onFileRequested != null) {
        onFileRequested();
      }

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

            var ip = svc.host ?? '';
            if (ip.isEmpty || ip == 'null') {
              final match = RegExp(r'Zync-(\d+)-(\d+)-(\d+)-(\d+)').firstMatch(svc.name);
              if (match != null) {
                ip = '${match.group(1)}.${match.group(2)}.${match.group(3)}.${match.group(4)}';
              }
            }

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

  /// Recursively archives a directory into a zip byte array.
  Future<List<int>> _archiveDirectory(Directory dir) async {
    final archive = Archive();
    final files = dir.listSync(recursive: true);

    for (final file in files) {
      if (file is File) {
        final relativePath = p.relative(file.path, from: dir.path);
        final fileBytes = await file.readAsBytes();
        archive.addFile(ArchiveFile(relativePath, fileBytes.length, fileBytes));
      }
    }

    return ZipEncoder().encode(archive);
  }

  /// Archives a list of files into a zip byte array.
  Future<List<int>> _archiveFiles(List<File> files) async {
    final archive = Archive();

    for (final file in files) {
      final relativePath = p.basename(file.path);
      final fileBytes = await file.readAsBytes();
      archive.addFile(ArchiveFile(relativePath, fileBytes.length, fileBytes));
    }

    return ZipEncoder().encode(archive);
  }

  /// Resolves all available local IPv4 addresses on the device,
  /// filtering out loopback and common virtual/tunnel/bridge interfaces.
  Future<List<String>> getAllLocalIps() async {
    final ips = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      
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
               !name.contains('wg') &&
               !name.contains('veth') &&
               !name.contains('br-') &&
               !name.contains('bridge') &&
               !name.contains('dummy') &&
               !name.contains('ifb');
      }).toList();

      for (final iface in validInterfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && !ips.contains(addr.address)) {
            ips.add(addr.address);
          }
        }
      }
    } catch (_) {}
    
    // Fallback: if empty, add whatever getLocalIp returns
    if (ips.isEmpty) {
      final primaryIp = await getLocalIp();
      ips.add(primaryIp);
    }
    return ips;
  }
}
