import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/p2p_service.dart';
import '../providers/device_info_provider.dart';

class SenderView extends ConsumerStatefulWidget {
  const SenderView({super.key});

  @override
  ConsumerState<SenderView> createState() => _SenderViewState();
}

class _SenderViewState extends ConsumerState<SenderView> {
  final P2PService _p2pService = P2PService();
  bool _isServerStarted = false;
  String? _qrData;

  @override
  void initState() {
    super.initState();
    _startServer();
  }

  Future<void> _startServer() async {
    // In a real app, pick a file first. For now, use a dummy file.
    final dummyFile = File('dummy.txt');
    await _p2pService.startServerAndBroadcast(dummyFile);

    // After starting, fetch device info and generate QR code
    final deviceInfo = await ref.read(deviceInfoProvider.future);
    
    final qrPayload = {
      "ip": "192.168.1.x", // Placeholder, since obtaining localized IP usually Requires network_info_plus
      "port": 8080,
      "name": deviceInfo.deviceName
    };

    setState(() {
      _qrData = jsonEncode(qrPayload);
      _isServerStarted = true;
    });
  }

  @override
  void dispose() {
    _p2pService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send File'),
      ),
      body: Center(
        child: _isServerStarted && _qrData != null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Scan this QR Code to connect:',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white, // QR code needs high contrast background
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: QrImageView(
                      data: _qrData!,
                      version: QrVersions.auto,
                      size: 250.0,
                    ),
                  ),
                  const SizedBox(height: 30),
                  const Text('Waiting for receiver...', style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 20),
                  const CircularProgressIndicator(),
                ],
              )
            : const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   CircularProgressIndicator(),
                   SizedBox(height: 20),
                   Text('Starting P2P Server...'),
                ],
              ),
      ),
    );
  }
}
