import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/p2p_service.dart';

class ReceiverView extends ConsumerStatefulWidget {
  const ReceiverView({super.key});

  @override
  ConsumerState<ReceiverView> createState() => _ReceiverViewState();
}

class _ReceiverViewState extends ConsumerState<ReceiverView> {
  final P2PService _p2pService = P2PService();

  @override
  void initState() {
    super.initState();
    _startDiscovery();
  }

  Future<void> _startDiscovery() async {
    await _p2pService.discoverDevices();
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
        title: const Text('Receive File'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.radar, size: 80, color: Colors.orange),
            const SizedBox(height: 20),
            const Text(
              'Looking for devices...',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),
            const CircularProgressIndicator(),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan QR Code instead'),
              onPressed: () {
                // Future integration for a QR scanner
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('QR Scanner not implemented yet')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
