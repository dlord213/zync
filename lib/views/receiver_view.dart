import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import '../main.dart';
import '../services/p2p_service.dart';

class ReceiverView extends ConsumerStatefulWidget {
  const ReceiverView({super.key});

  @override
  ConsumerState<ReceiverView> createState() => _ReceiverViewState();
}

class _ReceiverViewState extends ConsumerState<ReceiverView>
    with SingleTickerProviderStateMixin {
  final P2PService _p2pService = P2PService();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _startDiscovery();
  }

  Future<void> _startDiscovery() async {
    await _p2pService.discoverDevices();
  }

  @override
  void dispose() {
    _pulseController.dispose();
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
                        'Receive File',
                        style: Theme.of(context).textTheme.displayLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Looking for senders',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // --- Content ---
          SliverFillRemaining(
            hasScrollBody: false,
            child: _ReceiverContent(
              isDark: isDark,
              pulseAnimation: _pulseAnimation,
              onScanQr: () async {
                if (Platform.isAndroid) {
                  final result = await context.push('/qr-scan');
                  if (result != null && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Scanned QR Data: $result')),
                    );
                    // Add logic to connect to device here later
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Camera QR Scanner is only available on Android. (OneUI feature restriction)',
                      ),
                    ),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiverContent extends StatelessWidget {
  final bool isDark;
  final Animation<double> pulseAnimation;
  final VoidCallback onScanQr;

  const _ReceiverContent({
    required this.isDark,
    required this.pulseAnimation,
    required this.onScanQr,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Radar animation card
          Container(
            height: 240,
            decoration: BoxDecoration(
              color: isDark ? ZyncTheme.surface : Colors.white,
              borderRadius: BorderRadius.circular(ZyncTheme.radius),
            ),
            child: Center(
              child: AnimatedBuilder(
                animation: pulseAnimation,
                builder: (context, child) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // Outer pulse ring
                      Transform.scale(
                        scale: 1.0 + (1.0 - pulseAnimation.value) * 0.4,
                        child: Opacity(
                          opacity: pulseAnimation.value * 0.2,
                          child: Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: ZyncTheme.green,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Inner pulse ring
                      Transform.scale(
                        scale: pulseAnimation.value,
                        child: Opacity(
                          opacity: pulseAnimation.value * 0.5,
                          child: Container(
                            width: 90,
                            height: 90,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: ZyncTheme.green.withOpacity(0.12),
                            ),
                          ),
                        ),
                      ),
                      // Center icon
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: ZyncTheme.greenDim,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          LucideIcons.radar,
                          color: ZyncTheme.green,
                          size: 28,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Status info card
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
                    color: ZyncTheme.greenDim,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    LucideIcons.wifi,
                    color: ZyncTheme.green,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Looking for devices...',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
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
                    valueColor: AlwaysStoppedAnimation<Color>(ZyncTheme.green),
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // --- Scan QR Button (bottom-anchored per OneUI philosophy) ---
          GestureDetector(
            onTap: onScanQr,
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                color: isDark ? ZyncTheme.surface : Colors.white,
                borderRadius: BorderRadius.circular(ZyncTheme.radius),
                border: Border.all(
                  color: ZyncTheme.green.withOpacity(0.4),
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    LucideIcons.qrCode,
                    color: ZyncTheme.green,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Scan QR Code instead',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: ZyncTheme.green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
