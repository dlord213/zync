import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../main.dart';
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
    final dummyFile = File('dummy.txt');
    await _p2pService.startServerAndBroadcast(dummyFile);
    final deviceInfo = await ref.read(deviceInfoProvider.future);

    final qrPayload = {
      'ip': '192.168.1.x',
      'port': 8080,
      'name': deviceInfo.deviceName,
    };

    if (mounted) {
      setState(() {
        _qrData = jsonEncode(qrPayload);
        _isServerStarted = true;
      });
    }
  }

  @override
  void dispose() {
    _p2pService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? ZyncTheme.amoledBlack
          : Theme.of(context).colorScheme.surface,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // --- Large Collapsing AppBar ---
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            stretch: true,
            backgroundColor: isDark
                ? ZyncTheme.amoledBlack
                : Theme.of(context).colorScheme.surface,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(LucideIcons.arrowLeft),
              onPressed: () => Navigator.of(context).pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 20, bottom: 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Send File',
                        style: Theme.of(context).textTheme.displayLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Share via QR code',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // --- Content ---
          SliverToBoxAdapter(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height - 200,
              ),
              child: _isServerStarted && _qrData != null
                  ? _ServerReadyContent(qrData: _qrData!, isDark: isDark)
                  : _LoadingContent(isDark: isDark),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServerReadyContent extends StatelessWidget {
  final String qrData;
  final bool isDark;

  const _ServerReadyContent({required this.qrData, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // QR card
          Container(
            decoration: BoxDecoration(
              color: isDark ? ZyncTheme.surface : Colors.white,
              borderRadius: BorderRadius.circular(ZyncTheme.radius),
            ),
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: QrImageView(
                    data: qrData,
                    version: QrVersions.auto,
                    size: 220,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Color(0xFF000000),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Color(0xFF000000),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Scan with Zync on another device',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Status card
          Container(
            decoration: BoxDecoration(
              color: isDark ? ZyncTheme.surface : Colors.white,
              borderRadius: BorderRadius.circular(ZyncTheme.radius),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: ZyncTheme.orangeDim,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    LucideIcons.radio,
                    color: ZyncTheme.orange,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Server Running',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Listening on port 8080',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(ZyncTheme.orange),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingContent extends StatelessWidget {
  final bool isDark;
  const _LoadingContent({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: ZyncTheme.orangeDim,
              shape: BoxShape.circle,
            ),
            child: const CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(ZyncTheme.orange),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Starting server...',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'This will just take a moment',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
