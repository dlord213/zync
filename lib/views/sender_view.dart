import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../main.dart';
import '../services/p2p_service.dart';
import '../providers/device_info_provider.dart';
import '../providers/activity_log_provider.dart';
import '../models/activity_log.dart';

// ── State machine for the sender flow ────────────────────────────────────────
enum _SenderState { pickFile, startingServer, ready }

class SenderView extends ConsumerStatefulWidget {
  const SenderView({super.key});

  @override
  ConsumerState<SenderView> createState() => _SenderViewState();
}

class _SenderViewState extends ConsumerState<SenderView> {
  final P2PService _p2pService = P2PService();

  _SenderState _state = _SenderState.pickFile;
  File? _pickedFile;
  String? _qrData;
  String? _localIp;
  String? _errorMessage;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.any,
    );

    if (result == null || result.files.single.path == null) return;

    final file = File(result.files.single.path!);
    setState(() {
      _pickedFile = file;
      _state = _SenderState.startingServer;
      _errorMessage = null;
    });

    await _startServer(file);
  }

  Future<void> _startServer(File file) async {
    try {
      final deviceInfo = await ref.read(deviceInfoProvider.future);
      final fileName = file.path.split(Platform.pathSeparator).last;
      
      final ip = await _p2pService.startServerAndBroadcast(
        file,
        onFileRequested: () {
          ref.read(activityLogProvider.notifier).addLog(ActivityLog(
            fileName: fileName,
            targetDeviceName: 'Receiver Device',
            type: 'sent',
            timestamp: DateTime.now().millisecondsSinceEpoch,
          ));
        },
      );

      final qrPayload = {
        'ip': ip,
        'port': 8080,
        'name': deviceInfo.deviceName,
        'file': fileName,
      };

      if (mounted) {
        setState(() {
          _localIp = ip;
          _qrData = jsonEncode(qrPayload);
          _state = _SenderState.ready;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to start server: $e';
          _state = _SenderState.pickFile;
        });
      }
    }
  }

  Future<void> _changeFile() async {
    _p2pService.stop();
    setState(() {
      _state = _SenderState.pickFile;
      _pickedFile = null;
      _qrData = null;
      _localIp = null;
    });
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
                        _state == _SenderState.ready
                            ? 'Share the QR code below'
                            : 'Choose a file to share',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height - 200,
              ),
              child: switch (_state) {
                _SenderState.pickFile => _PickFileContent(
                    isDark: isDark,
                    errorMessage: _errorMessage,
                    onPick: _pickFile,
                  ),
                _SenderState.startingServer => _LoadingContent(
                    isDark: isDark,
                    fileName: _pickedFile?.path
                            .split(Platform.pathSeparator)
                            .last ??
                        '',
                  ),
                _SenderState.ready => _ServerReadyContent(
                    isDark: isDark,
                    qrData: _qrData!,
                    localIp: _localIp!,
                    file: _pickedFile!,
                    onChangeFile: _changeFile,
                  ),
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pick file screen ──────────────────────────────────────────────────────────
class _PickFileContent extends StatelessWidget {
  final bool isDark;
  final String? errorMessage;
  final VoidCallback onPick;

  const _PickFileContent({
    required this.isDark,
    required this.errorMessage,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Big tap-to-pick card
          GestureDetector(
            onTap: onPick,
            child: Container(
              height: 220,
              decoration: BoxDecoration(
                color: isDark ? ZyncTheme.surface : Colors.white,
                borderRadius: BorderRadius.circular(ZyncTheme.radius),
                border: Border.all(
                  color: ZyncTheme.orange.withOpacity(0.35),
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: ZyncTheme.orangeDim,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      LucideIcons.upload,
                      color: ZyncTheme.orange,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Tap to choose a file',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: ZyncTheme.orange,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Any file type supported',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),

          if (errorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(ZyncTheme.radiusSm),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.circleAlert,
                      color: Colors.red, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      errorMessage!,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Tips card
          Container(
            decoration: BoxDecoration(
              color: isDark ? ZyncTheme.surface : Colors.white,
              borderRadius: BorderRadius.circular(ZyncTheme.radius),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('How it works',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                _StepRow(
                    icon: LucideIcons.filePlus,
                    step: '1',
                    text: 'Choose a file to share'),
                _StepRow(
                    icon: LucideIcons.qrCode,
                    step: '2',
                    text: 'A QR code is generated with your IP'),
                _StepRow(
                    icon: LucideIcons.smartphoneNfc,
                    step: '3',
                    text: 'Receiver scans QR on another Zync device'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final IconData icon;
  final String step;
  final String text;
  const _StepRow(
      {required this.icon, required this.step, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: ZyncTheme.orangeDim,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: ZyncTheme.orange, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(text,
                style: Theme.of(context).textTheme.bodyLarge),
          ),
        ],
      ),
    );
  }
}

// ── Starting server screen ────────────────────────────────────────────────────
class _LoadingContent extends StatelessWidget {
  final bool isDark;
  final String fileName;
  const _LoadingContent({required this.isDark, required this.fileName});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: const BoxDecoration(
                color: ZyncTheme.orangeDim,
                shape: BoxShape.circle,
              ),
              child: const CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(ZyncTheme.orange),
              ),
            ),
            const SizedBox(height: 28),
            Text('Starting server…',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              fileName.isEmpty ? 'Please wait' : 'Preparing "$fileName"',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Ready (server running) screen ─────────────────────────────────────────────
class _ServerReadyContent extends StatelessWidget {
  final bool isDark;
  final String qrData;
  final String localIp;
  final File file;
  final VoidCallback onChangeFile;

  const _ServerReadyContent({
    required this.isDark,
    required this.qrData,
    required this.localIp,
    required this.file,
    required this.onChangeFile,
  });

  String get _fileName => file.path.split(Platform.pathSeparator).last;

  String get _fileSize {
    try {
      final bytes = file.lengthSync();
      if (bytes < 1024) return '$bytes B';
      if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
      if (bytes < 1073741824)
        return '${(bytes / 1048576).toStringAsFixed(1)} MB';
      return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
    } catch (_) {
      return '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // File info chip
          Container(
            decoration: BoxDecoration(
              color: isDark ? ZyncTheme.surface : Colors.white,
              borderRadius: BorderRadius.circular(ZyncTheme.radius),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: ZyncTheme.orangeDim,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(LucideIcons.file,
                      color: ZyncTheme.orange, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _fileName,
                        style:
                            Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(_fileSize,
                          style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onChangeFile,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: ZyncTheme.orangeDim,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Change',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: ZyncTheme.orange,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // QR code card
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
                    size: 200,
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
                const SizedBox(height: 16),
                Text(
                  'Scan with Zync on another device',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Server status card
          Container(
            decoration: BoxDecoration(
              color: isDark ? ZyncTheme.surface : Colors.white,
              borderRadius: BorderRadius.circular(ZyncTheme.radius),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: ZyncTheme.orangeDim,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(LucideIcons.radio,
                      color: ZyncTheme.orange, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Server running',
                        style:
                            Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                      Text(
                        'http://$localIp:8080',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(ZyncTheme.orange),
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
