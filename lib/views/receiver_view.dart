import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import '../main.dart';
import '../services/p2p_service.dart';

// ── Transfer state machine ────────────────────────────────────────────────────
enum _TransferPhase { idle, connecting, downloading, done, error }

// ── Radar blip model ──────────────────────────────────────────────────────────
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

  // ── Radar animation controllers ───────────────────────────────────────────
  late AnimationController _sweepController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _blipController;
  late Animation<double> _blipAnimation;

  // ── Discovery state ───────────────────────────────────────────────────────
  final List<_RadarDevice> _foundDevices = [];
  final _rng = Random();
  StreamSubscription<DiscoveredDevice>? _discoverySub;

  // ── Transfer state ────────────────────────────────────────────────────────
  _TransferPhase _phase = _TransferPhase.idle;
  double _downloadProgress = 0;
  String? _savedFilePath;
  String? _transferError;
  String? _incomingFileName;

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
      final key = '${device.ip}:${device.port}';
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

  // ── QR scan → connect → download ─────────────────────────────────────────

  Future<void> _handleQrResult(String rawJson) async {
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(rawJson) as Map<String, dynamic>;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _TransferPhase.error;
        _transferError = 'Invalid QR code. Please scan a Zync QR code.';
      });
      return;
    }

    final ip = payload['ip'] as String?;
    final port = (payload['port'] as num?)?.toInt() ?? 8080;
    final fileName = (payload['file'] as String?) ?? 'zync_received_file';

    if (ip == null || ip.isEmpty) {
      setState(() {
        _phase = _TransferPhase.error;
        _transferError = 'QR code does not contain a valid IP address.';
      });
      return;
    }

    await _startDownload(ip, port, defaultFileName: fileName);
  }

  Future<void> _startDownload(String ip, int port, {String? defaultFileName}) async {
    setState(() {
      _phase = _TransferPhase.connecting;
      _incomingFileName = defaultFileName ?? 'Connecting to sender...';
      _downloadProgress = 0;
      _savedFilePath = null;
      _transferError = null;
    });

    try {
      final url = Uri.parse('http://$ip:$port/');
      print('Connecting to sender at $url');

      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10);
      final request = await client.getUrl(url);
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception('Server responded with ${response.statusCode}');
      }

      // Try to parse filename from headers if one was provided by the Sender
      String fileName = defaultFileName ?? 'zync_received_file';
      final disposition = response.headers.value('content-disposition');
      if (disposition != null) {
        final match = RegExp(r'filename="([^"]+)"').firstMatch(disposition);
        if (match != null && match.groupCount >= 1) {
          fileName = match.group(1) ?? fileName;
        }
      }

      setState(() {
        _phase = _TransferPhase.downloading;
        _incomingFileName = fileName;
      });

      // Resolve save directory
      Directory dir;
      if (Platform.isAndroid) {
        dir = Directory('/storage/emulated/0/Download/Zync');
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      } else {
        final d = await getDownloadsDirectory();
        if (d != null) {
          dir = Directory('${d.path}${Platform.pathSeparator}Zync');
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
        } else {
          dir = await getApplicationDocumentsDirectory();
        }
      }

      // Avoid overwriting existing files
      String savePath = '${dir.path}/$fileName';
      int suffix = 1;
      while (File(savePath).existsSync()) {
        final dot = fileName.lastIndexOf('.');
        if (dot != -1) {
          savePath =
              '${dir.path}/${fileName.substring(0, dot)}($suffix)${fileName.substring(dot)}';
        } else {
          savePath = '${dir.path}/$fileName($suffix)';
        }
        suffix++;
      }

      final file = File(savePath);
      final sink = file.openWrite();
      final totalBytes = response.contentLength; // -1 if unknown
      int downloaded = 0;

      await for (final chunk in response) {
        sink.add(chunk);
        downloaded += chunk.length;
        if (totalBytes > 0 && mounted) {
          setState(() => _downloadProgress = downloaded / totalBytes);
        }
      }

      await sink.flush();
      await sink.close();
      client.close();

      print('File saved to: $savePath');

      if (mounted) {
        setState(() {
          _phase = _TransferPhase.done;
          _savedFilePath = savePath;
          _downloadProgress = 1.0;
        });
      }
    } on SocketException catch (e) {
      if (mounted) {
        setState(() {
          _phase = _TransferPhase.error;
          _transferError =
              'Could not reach sender at $ip:$port.\nMake sure both devices are on the same Wi-Fi network.\n\nDetail: ${e.message}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _TransferPhase.error;
          _transferError = e.toString();
        });
      }
    }
  }

  void _resetToIdle() {
    setState(() {
      _phase = _TransferPhase.idle;
      _downloadProgress = 0;
      _savedFilePath = null;
      _transferError = null;
      _incomingFileName = null;
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
                        _phase == _TransferPhase.idle
                            ? 'Scan QR or wait for discovery'
                            : _phase == _TransferPhase.done
                                ? 'Transfer complete'
                                : _phase == _TransferPhase.error
                                    ? 'Transfer failed'
                                    : 'Receiving file…',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          SliverFillRemaining(
            hasScrollBody: false,
            child: switch (_phase) {
              _TransferPhase.idle => _ReceiverContent(
                  isDark: isDark,
                  pulseAnimation: _pulseAnimation,
                  sweepAnimation: _sweepController,
                  blipAnimation: _blipAnimation,
                  foundDevices: _foundDevices,
                  onScanQr: () async {
                    if (Platform.isAndroid) {
                      final result = await context.push<String>('/qr-scan');
                      if (result != null && mounted) {
                        await _handleQrResult(result);
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
                  onDeviceTap: (device) {
                    _startDownload(device.ip, device.port);
                  },
                ),
              _TransferPhase.connecting => _TransferProgressContent(
                  isDark: isDark,
                  phase: _phase,
                  fileName: _incomingFileName ?? '',
                  progress: 0,
                ),
              _TransferPhase.downloading => _TransferProgressContent(
                  isDark: isDark,
                  phase: _phase,
                  fileName: _incomingFileName ?? '',
                  progress: _downloadProgress,
                ),
              _TransferPhase.done => _TransferDoneContent(
                  isDark: isDark,
                  fileName: _incomingFileName ?? 'File',
                  savedPath: _savedFilePath ?? '',
                  onReceiveAnother: _resetToIdle,
                ),
              _TransferPhase.error => _TransferErrorContent(
                  isDark: isDark,
                  error: _transferError ?? 'Unknown error.',
                  onRetry: _resetToIdle,
                ),
            },
          ),
        ],
      ),
    );
  }
}

// ── Radar screen (idle) ───────────────────────────────────────────────────────
class _ReceiverContent extends StatelessWidget {
  final bool isDark;
  final Animation<double> pulseAnimation;
  final AnimationController sweepAnimation;
  final Animation<double> blipAnimation;
  final List<_RadarDevice> foundDevices;
  final VoidCallback onScanQr;
  final Function(DiscoveredDevice) onDeviceTap;

  const _ReceiverContent({
    required this.isDark,
    required this.pulseAnimation,
    required this.sweepAnimation,
    required this.blipAnimation,
    required this.foundDevices,
    required this.onScanQr,
    required this.onDeviceTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Radar card ───────────────────────────────────────────
          Container(
            height: 300,
            decoration: BoxDecoration(
              color: isDark ? ZyncTheme.surface : Colors.white,
              borderRadius: BorderRadius.circular(ZyncTheme.radius),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(ZyncTheme.radius),
              child: AnimatedBuilder(
                animation: Listenable.merge(
                    [sweepAnimation, pulseAnimation, blipAnimation]),
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

          // ── Device list / status card ────────────────────────────
          if (foundDevices.isEmpty)
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
                    child: const Icon(LucideIcons.wifi, color: ZyncTheme.green, size: 20),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Scanning for devices…',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
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
            )
          else ...[
            Text(
              'Found Devices',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            ...foundDevices.map((d) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GestureDetector(
                    onTap: () => onDeviceTap(d.source),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? ZyncTheme.surface : Colors.white,
                        borderRadius: BorderRadius.circular(ZyncTheme.radius),
                        border: Border.all(color: ZyncTheme.green.withOpacity(0.1)),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: const BoxDecoration(
                              color: ZyncTheme.greenDim,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(LucideIcons.smartphone, color: ZyncTheme.green, size: 22),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  d.name,
                                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                                Text(
                                  'Tap to receive file',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          const Icon(LucideIcons.chevronRight, color: ZyncTheme.green),
                        ],
                      ),
                    ),
                  ),
                )),
          ],

          const Spacer(),

          // ── Scan QR button (bottom-anchored) ─────────────────────
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
                  const Icon(LucideIcons.qrCode,
                      color: ZyncTheme.green, size: 20),
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

// ── Downloading screen ────────────────────────────────────────────────────────
class _TransferProgressContent extends StatelessWidget {
  final bool isDark;
  final _TransferPhase phase;
  final String fileName;
  final double progress;

  const _TransferProgressContent({
    required this.isDark,
    required this.phase,
    required this.fileName,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final isConnecting = phase == _TransferPhase.connecting;
    final pct = (progress * 100).toStringAsFixed(0);

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: ZyncTheme.greenDim,
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: CircularProgressIndicator(
                  value: isConnecting ? null : progress,
                  strokeWidth: 4,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(ZyncTheme.green),
                ),
              ),
            ),
          ),

          const SizedBox(height: 32),

          Text(
            isConnecting ? 'Connecting to sender…' : 'Downloading…',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 10),

          Text(
            fileName.isEmpty ? 'Please wait' : '"$fileName"',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),

          if (!isConnecting) ...[
            const SizedBox(height: 28),

            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(ZyncTheme.green),
                backgroundColor: ZyncTheme.greenDim,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              '$pct%',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: ZyncTheme.green,
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Done screen ───────────────────────────────────────────────────────────────
class _TransferDoneContent extends StatelessWidget {
  final bool isDark;
  final String fileName;
  final String savedPath;
  final VoidCallback onReceiveAnother;

  const _TransferDoneContent({
    required this.isDark,
    required this.fileName,
    required this.savedPath,
    required this.onReceiveAnother,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 100,
              height: 100,
              decoration: const BoxDecoration(
                color: ZyncTheme.greenDim,
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.circleCheck,
                  color: ZyncTheme.green, size: 46),
            ),
          ),

          const SizedBox(height: 32),

          Text(
            'File Received',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 10),

          Text(
            '"$fileName" was saved successfully.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 16),

          // Saved path chip
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? ZyncTheme.surface : Colors.white,
              borderRadius: BorderRadius.circular(ZyncTheme.radiusSm),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.folderOpen,
                    color: ZyncTheme.green, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    savedPath,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ZyncTheme.green,
                        ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          GestureDetector(
            onTap: onReceiveAnother,
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                color: ZyncTheme.green,
                borderRadius: BorderRadius.circular(ZyncTheme.radius),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(LucideIcons.plus,
                      color: Colors.black, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'Receive Another File',
                    style:
                        Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Colors.black,
                              fontWeight: FontWeight.w700,
                            ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Error screen ──────────────────────────────────────────────────────────────
class _TransferErrorContent extends StatelessWidget {
  final bool isDark;
  final String error;
  final VoidCallback onRetry;

  const _TransferErrorContent({
    required this.isDark,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.circleX,
                  color: Colors.red, size: 46),
            ),
          ),

          const SizedBox(height: 32),

          Text(
            'Transfer Failed',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? ZyncTheme.surface : Colors.white,
              borderRadius: BorderRadius.circular(ZyncTheme.radiusSm),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: Text(
              error,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(height: 32),

          GestureDetector(
            onTap: onRetry,
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                color: isDark ? ZyncTheme.surface : Colors.white,
                borderRadius: BorderRadius.circular(ZyncTheme.radius),
                border: Border.all(
                    color: ZyncTheme.green.withOpacity(0.4), width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(LucideIcons.rotateCcw,
                      color: ZyncTheme.green, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'Try Again',
                    style:
                        Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: ZyncTheme.green,
                              fontWeight: FontWeight.w600,
                            ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Radar painter (unchanged) ─────────────────────────────────────────────────
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

    final bgPaint = Paint()
      ..color = isDark
          ? const Color(0xFF0D1A0D)
          : const Color(0xFFECF8EE);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final ringPaint = Paint()
      ..color = ZyncTheme.green.withOpacity(0.12)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(Offset(cx, cy), maxR * (i / 3), ringPaint);
    }

    final linePaint = Paint()
      ..color = ZyncTheme.green.withOpacity(0.1)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(cx - maxR, cy), Offset(cx + maxR, cy), linePaint);
    canvas.drawLine(Offset(cx, cy - maxR), Offset(cx, cy + maxR), linePaint);

    const sweepSpan = pi / 2;
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

    final leadPaint = Paint()
      ..color = ZyncTheme.green.withOpacity(0.6)
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + maxR * cos(sweepAngle), cy + maxR * sin(sweepAngle)),
      leadPaint,
    );

    final borderPaint = Paint()
      ..color = ZyncTheme.green.withOpacity(0.25)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(Offset(cx, cy), maxR, borderPaint);

    final pulseR = maxR * pulseValue;
    final pulsePaint = Paint()
      ..color = ZyncTheme.green.withOpacity((1 - pulseValue) * 0.3)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(Offset(cx, cy), pulseR, pulsePaint);

    for (final device in devices) {
      final dx = cx + device.distance * maxR * cos(device.angle);
      final dy = cy + device.distance * maxR * sin(device.angle);

      final haloPaint = Paint()
        ..color = ZyncTheme.green.withOpacity(0.15 * blipValue);
      canvas.drawCircle(Offset(dx, dy), 16 * blipValue, haloPaint);

      final blipPaint = Paint()..color = ZyncTheme.green;
      canvas.drawCircle(Offset(dx, dy), 5.5, blipPaint);

      _drawUserIcon(canvas, Offset(dx, dy - 14));
    }

    final centerGlow = Paint()..color = ZyncTheme.green.withOpacity(0.18);
    canvas.drawCircle(Offset(cx, cy), 18, centerGlow);
    final centerPaint = Paint()..color = ZyncTheme.green;
    canvas.drawCircle(Offset(cx, cy), 6, centerPaint);
  }

  void _drawUserIcon(Canvas canvas, Offset pos) {
    final paint = Paint()
      ..color = ZyncTheme.green.withOpacity(0.85)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pos, 4.0, paint);

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
