import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import '../main.dart';
import '../services/p2p_service.dart';

// A device placed on the radar canvas
class _RadarDevice {
  final String name;
  final double angle;    // radians – randomised for visual spread
  final double distance; // 0.0–1.0 fraction of radar radius
  final DiscoveredDevice source;

  const _RadarDevice({
    required this.name,
    required this.angle,
    required this.distance,
    required this.source,
  });
}

class ReceiverView extends ConsumerStatefulWidget {
  const ReceiverView({super.key});

  @override
  ConsumerState<ReceiverView> createState() => _ReceiverViewState();
}

class _ReceiverViewState extends ConsumerState<ReceiverView>
    with TickerProviderStateMixin {
  final P2PService _p2pService = P2PService();

  // Slow sweep for the radar line
  late AnimationController _sweepController;

  // Fast repeating pulse for the rings
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Per-device pulse so blips breathe independently
  late AnimationController _blipController;
  late Animation<double> _blipAnimation;

  final List<_RadarDevice> _foundDevices = [];
  final _rng = Random();
  StreamSubscription<DiscoveredDevice>? _discoverySub;

  @override
  void initState() {
    super.initState();

    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _blipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _blipAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _blipController, curve: Curves.easeInOut),
    );

    _startDiscovery();
  }

  void _startDiscovery() {
    final seen = <String>{};
    _discoverySub = _p2pService.discoverDevices().listen((device) {
      final key = '${device.host}:${device.port}';
      if (seen.contains(key)) return;
      seen.add(key);
      if (!mounted) return;
      setState(() {
        _foundDevices.add(_RadarDevice(
          name: device.name,
          angle: _rng.nextDouble() * 2 * pi,
          distance: 0.3 + _rng.nextDouble() * 0.55,
          source: device,
        ));
      });
    });
  }

  @override
  void dispose() {
    _discoverySub?.cancel();
    _sweepController.dispose();
    _pulseController.dispose();
    _blipController.dispose();
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
              sweepAnimation: _sweepController,
              blipAnimation: _blipAnimation,
              foundDevices: _foundDevices,
              isScanning: _foundDevices.isEmpty,
              onScanQr: () async {
                if (Platform.isAndroid) {
                  final result = await context.push('/qr-scan');
                  if (result != null && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Scanned QR Data: $result')),
                    );
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Camera QR Scanner is only available on Android.',
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
  final AnimationController sweepAnimation;
  final Animation<double> blipAnimation;
  final List<_RadarDevice> foundDevices;
  final bool isScanning;
  final VoidCallback onScanQr;

  const _ReceiverContent({
    required this.isDark,
    required this.pulseAnimation,
    required this.sweepAnimation,
    required this.blipAnimation,
    required this.foundDevices,
    required this.isScanning,
    required this.onScanQr,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Radar card ──────────────────────────────────────────
          Container(
            height: 300,
            decoration: BoxDecoration(
              color: isDark ? ZyncTheme.surface : Colors.white,
              borderRadius: BorderRadius.circular(ZyncTheme.radius),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(ZyncTheme.radius),
              child: AnimatedBuilder(
                animation: Listenable.merge([sweepAnimation, pulseAnimation, blipAnimation]),
                builder: (context, _) {
                  return CustomPaint(
                    painter: _RadarPainter(
                      sweepAngle: sweepAnimation.value * 2 * pi,
                      pulseValue: pulseAnimation.value,
                      blipValue: blipAnimation.value,
                      devices: foundDevices,
                      isDark: isDark,
                    ),
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ── Device count / status card ────────────────────────
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
                    color: foundDevices.isNotEmpty
                        ? ZyncTheme.greenDim
                        : ZyncTheme.greenDim,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    foundDevices.isNotEmpty
                        ? LucideIcons.usersRound
                        : LucideIcons.wifi,
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
                        foundDevices.isEmpty
                            ? 'Scanning for devices...'
                            : '${foundDevices.length} device${foundDevices.length == 1 ? '' : 's'} found',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (foundDevices.isNotEmpty)
                        Text(
                          foundDevices.map((d) => d.name).join(', '),
                          style: Theme.of(context).textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (foundDevices.isEmpty)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(ZyncTheme.green),
                    ),
                  ),
                if (foundDevices.isNotEmpty)
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: ZyncTheme.green,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),

          const Spacer(),

          // ── Scan QR button (bottom-anchored) ─────────────────
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

// ── Custom painter for the radar ─────────────────────────────────────────────
class _RadarPainter extends CustomPainter {
  final double sweepAngle;
  final double pulseValue;
  final double blipValue;
  final List<_RadarDevice> devices;
  final bool isDark;

  _RadarPainter({
    required this.sweepAngle,
    required this.pulseValue,
    required this.blipValue,
    required this.devices,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final maxR = min(cx, cy) * 0.88;

    // ── Background fill ────────────────────────────────────────
    final bgPaint = Paint()
      ..color = isDark
          ? const Color(0xFF0D1A0D)
          : const Color(0xFFECF8EE);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // ── Grid rings ─────────────────────────────────────────────
    final ringPaint = Paint()
      ..color = ZyncTheme.green.withOpacity(0.12)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(Offset(cx, cy), maxR * (i / 3), ringPaint);
    }

    // ── Cross-hair lines ───────────────────────────────────────
    final linePaint = Paint()
      ..color = ZyncTheme.green.withOpacity(0.1)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(cx - maxR, cy), Offset(cx + maxR, cy), linePaint);
    canvas.drawLine(Offset(cx, cy - maxR), Offset(cx, cy + maxR), linePaint);

    // ── Sweep sector (trailing gradient glow) ─────────────────
    const sweepSpan = pi / 2; // 90° sweep trail
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        center: Alignment.center,
        startAngle: sweepAngle - sweepSpan,
        endAngle: sweepAngle,
        colors: [
          ZyncTheme.green.withOpacity(0.0),
          ZyncTheme.green.withOpacity(0.18),
        ],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: maxR));
    canvas.drawCircle(Offset(cx, cy), maxR, sweepPaint);

    // ── Sweep leading line ─────────────────────────────────────
    final leadPaint = Paint()
      ..color = ZyncTheme.green.withOpacity(0.6)
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + maxR * cos(sweepAngle), cy + maxR * sin(sweepAngle)),
      leadPaint,
    );

    // ── Outer border of radar circle ───────────────────────────
    final borderPaint = Paint()
      ..color = ZyncTheme.green.withOpacity(0.25)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(Offset(cx, cy), maxR, borderPaint);

    // ── Pulsing ring (emanates from center) ────────────────────
    final pulseR = maxR * pulseValue;
    final pulsePaint = Paint()
      ..color = ZyncTheme.green.withOpacity((1 - pulseValue) * 0.3)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(Offset(cx, cy), pulseR, pulsePaint);

    // ── Device blips ───────────────────────────────────────────
    for (final device in devices) {
      final dx = cx + device.distance * maxR * cos(device.angle);
      final dy = cy + device.distance * maxR * sin(device.angle);

      // Pulsing glow halo around blip
      final haloPaint = Paint()
        ..color = ZyncTheme.green.withOpacity(0.15 * blipValue);
      canvas.drawCircle(Offset(dx, dy), 16 * blipValue, haloPaint);

      // Blip filled circle
      final blipPaint = Paint()..color = ZyncTheme.green;
      canvas.drawCircle(Offset(dx, dy), 5.5, blipPaint);

      // User silhouette icon using a path-based mini circle (head + shoulders)
      _drawUserIcon(canvas, Offset(dx, dy - 14));
    }

    // ── Center scanner dot ─────────────────────────────────────
    final centerGlow = Paint()
      ..color = ZyncTheme.green.withOpacity(0.18);
    canvas.drawCircle(Offset(cx, cy), 18, centerGlow);
    final centerPaint = Paint()..color = ZyncTheme.green;
    canvas.drawCircle(Offset(cx, cy), 6, centerPaint);
  }

  void _drawUserIcon(Canvas canvas, Offset pos) {
    final paint = Paint()
      ..color = ZyncTheme.green.withOpacity(0.85)
      ..style = PaintingStyle.fill;

    // Head
    canvas.drawCircle(pos, 4.0, paint);

    // Shoulders arc suggestion
    final shoulderPaint = Paint()
      ..color = ZyncTheme.green.withOpacity(0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(pos.dx - 5, pos.dy + 8)
      ..quadraticBezierTo(pos.dx, pos.dy + 4, pos.dx + 5, pos.dy + 8);
    canvas.drawPath(path, shoulderPaint);
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.sweepAngle != sweepAngle ||
      old.pulseValue != pulseValue ||
      old.blipValue != blipValue ||
      old.devices.length != devices.length;
}
