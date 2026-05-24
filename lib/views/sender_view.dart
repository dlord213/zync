import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:path/path.dart' as p;
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
  dynamic _pickedEntity;
  String? _qrData;
  String? _localIp;
  String? _errorMessage;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
    );

    if (result == null || result.files.isEmpty) return;

    dynamic picked;
    if (result.files.length == 1) {
      picked = File(result.files.single.path!);
    } else {
      picked = result.files.map((f) => File(f.path!)).toList();
    }

    setState(() {
      _pickedEntity = picked;
      _state = _SenderState.startingServer;
      _errorMessage = null;
    });

    await _startServer(picked);
  }

  Future<void> _pickFolder() async {
    final result = await FilePicker.platform.getDirectoryPath();

    if (result == null) return;

    final dir = Directory(result);
    setState(() {
      _pickedEntity = dir;
      _state = _SenderState.startingServer;
      _errorMessage = null;
    });

    await _startServer(dir);
  }

  Future<void> _startServer(dynamic entity) async {
    try {
      final deviceInfo = await ref.read(deviceInfoProvider.future);
      String fileName;
      if (entity is Directory) {
        fileName = p.basename(entity.path);
      } else if (entity is File) {
        fileName = p.basename(entity.path);
      } else if (entity is List<File>) {
        fileName = 'Files.zync';
      } else {
        fileName = 'Unknown';
      }

      final ip = await _p2pService.startServerAndBroadcast(
        entity,
        onFileRequested: () {
          ref
              .read(activityLogProvider.notifier)
              .addLog(
                ActivityLog(
                  fileName: entity is Directory
                      ? '$fileName (Folder)'
                      : (entity is List ? 'Multiple Files' : fileName),
                  targetDeviceName: 'Receiver Device',
                  type: 'sent',
                  timestamp: DateTime.now().millisecondsSinceEpoch,
                ),
              );
        },
      );

      final ips = await _p2pService.getAllLocalIps();

      final qrPayload = {
        'ip': ip,
        'ips': ips,
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
      _pickedEntity = null;
      _qrData = null;
      _localIp = null;
    });
  }

  Future<void> _refreshServer() async {
    if (_pickedEntity != null) {
      setState(() {
        _state = _SenderState.startingServer;
      });
      await _startServer(_pickedEntity!);
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
                            : 'Choose a file/folder to share',
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
                  onPickFile: _pickFile,
                  onPickFolder: _pickFolder,
                  onOpenHotspot: () async {
                    final success = await _p2pService.openHotspotSettings();
                    if (!success && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Could not open Settings automatically. Please open Settings > Hotspot manually. (Restart app if recently updated).',
                          ),
                        ),
                      );
                    }
                  },
                ),
                _SenderState.startingServer => _LoadingContent(
                  isDark: isDark,
                  fileName: _pickedEntity is List ? 'Multiple Files' : p.basename((_pickedEntity as FileSystemEntity?)?.path ?? ''),
                ),
                _SenderState.ready => _ServerReadyContent(
                  isDark: isDark,
                  qrData: _qrData!,
                  localIp: _localIp!,
                  entity: _pickedEntity!,
                  onChangeFile: _changeFile,
                  onOpenHotspot: () async {
                    final success = await _p2pService.openHotspotSettings();
                    if (!success && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Could not open Settings automatically. Please open Settings > Hotspot manually. (Restart app if recently updated).',
                          ),
                        ),
                      );
                    }
                  },
                  onRefresh: _refreshServer,
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
  final VoidCallback onPickFile;
  final VoidCallback onPickFolder;
  final VoidCallback onOpenHotspot;

  const _PickFileContent({
    required this.isDark,
    required this.errorMessage,
    required this.onPickFile,
    required this.onPickFolder,
    required this.onOpenHotspot,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Big tap-to-pick card (File)
          GestureDetector(
            onTap: onPickFile,
            child: Container(
              height: 160,
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
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: ZyncTheme.orangeDim,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      LucideIcons.filePlus,
                      color: ZyncTheme.orange,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Pick File/s',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: ZyncTheme.orange,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Big tap-to-pick card (Folder)
          GestureDetector(
            onTap: onPickFolder,
            child: Container(
              height: 160,
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
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: ZyncTheme.orangeDim,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      LucideIcons.folderPlus,
                      color: ZyncTheme.orange,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Pick a Folder',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: ZyncTheme.orange,
                      fontSize: 18,
                    ),
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
                  const Icon(
                    LucideIcons.circleAlert,
                    color: Colors.red,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      errorMessage!,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Hotspot Card
          Container(
            decoration: BoxDecoration(
              color: isDark ? ZyncTheme.surface : Colors.white,
              borderRadius: BorderRadius.circular(ZyncTheme.radius),
              border: Border.all(
                color: ZyncTheme.green.withOpacity(0.2),
                width: 1.5,
              ),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
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
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Direct Hotspot Mode',
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Faster transfer, bypasses router blocks',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        LucideIcons.info,
                        color: ZyncTheme.green,
                        size: 22,
                      ),
                      onPressed: () => _showHotspotHelp(context, isDark),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: ZyncTheme.green,
                          side: BorderSide(
                            color: ZyncTheme.green.withOpacity(0.5),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              ZyncTheme.radiusSm,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(LucideIcons.settings, size: 18),
                        label: const Text(
                          'Enable Hotspot',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onPressed: onOpenHotspot,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

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
                Text(
                  'How it works',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                _StepRow(
                  icon: LucideIcons.filePlus,
                  step: '1',
                  text: 'Choose a file/folder to share',
                ),
                _StepRow(
                  icon: LucideIcons.qrCode,
                  step: '2',
                  text: 'A QR code is generated with your IP',
                ),
                _StepRow(
                  icon: LucideIcons.smartphoneNfc,
                  step: '3',
                  text: 'Receiver scans QR on another Zync device',
                ),
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
  const _StepRow({required this.icon, required this.step, required this.text});

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
            child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
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
            Text(
              'Starting server…',
              style: Theme.of(context).textTheme.titleLarge,
            ),
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
  final dynamic entity;
  final VoidCallback onChangeFile;
  final VoidCallback onOpenHotspot;
  final VoidCallback onRefresh;

  const _ServerReadyContent({
    required this.isDark,
    required this.qrData,
    required this.localIp,
    required this.entity,
    required this.onChangeFile,
    required this.onOpenHotspot,
    required this.onRefresh,
  });

  String get _fileName {
    if (entity is List) return 'Multiple Files';
    return p.basename((entity as FileSystemEntity).path);
  }

  String get _displaySize {
    try {
      if (entity is File) {
        final bytes = (entity as File).lengthSync();
        return _formatSize(bytes);
      } else if (entity is Directory) {
        int total = 0;
        final list = (entity as Directory).listSync(recursive: true);
        for (var f in list) {
          if (f is File) total += f.lengthSync();
        }
        return '${list.whereType<File>().length} files, ${_formatSize(total)}';
      } else if (entity is List) {
        int total = 0;
        for (var f in (entity as List)) {
          if (f is File) total += f.lengthSync();
        }
        return '${(entity as List).length} files, ${_formatSize(total)}';
      }
      return '—';
    } catch (_) {
      return '—';
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
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
                  child: Icon(
                    entity is Directory ? LucideIcons.folder : (entity is List ? LucideIcons.files : LucideIcons.file),
                    color: ZyncTheme.orange,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _fileName,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _displaySize,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onChangeFile,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
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
                  child: const Icon(
                    LucideIcons.radio,
                    color: ZyncTheme.orange,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Server running',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
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
                    valueColor: AlwaysStoppedAnimation<Color>(ZyncTheme.orange),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Hotspot management & troubleshooting card
          Container(
            decoration: BoxDecoration(
              color: isDark ? ZyncTheme.surface : Colors.white,
              borderRadius: BorderRadius.circular(ZyncTheme.radius),
              border: Border.all(
                color: ZyncTheme.green.withOpacity(0.15),
                width: 1,
              ),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: ZyncTheme.greenDim,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        LucideIcons.wifi,
                        color: ZyncTheme.green,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Direct Hotspot Mode',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        LucideIcons.info,
                        color: ZyncTheme.green,
                        size: 20,
                      ),
                      onPressed: () => _showHotspotHelp(context, isDark),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'If the receiver cannot connect, enable your mobile hotspot, connect the receiver to it, and tap Refresh.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: ZyncTheme.green,
                          side: BorderSide(
                            color: ZyncTheme.green.withOpacity(0.4),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              ZyncTheme.radiusSm,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: onOpenHotspot,
                        child: const Text('Hotspot Settings'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ZyncTheme.orange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              ZyncTheme.radiusSm,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          elevation: 0,
                        ),
                        icon: const Icon(LucideIcons.refreshCw, size: 14),
                        label: const Text('Refresh QR'),
                        onPressed: onRefresh,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Hotspot Help Bottom Sheet and Utilities ───────────────────────────────────

void _showHotspotHelp(BuildContext context, bool isDark) {
  showBottomSheet(
    context: context,
    backgroundColor: isDark ? ZyncTheme.surface : Colors.white,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(ZyncTheme.radius),
      ),
    ),
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Wi-Fi Hotspot Sharing',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.x),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Creating a temporary Wi-Fi hotspot on your device is the fastest and most reliable way to transfer files between devices.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                _buildBenefitRow(
                  context,
                  icon: LucideIcons.zap,
                  title: 'Maximum Speed',
                  subtitle:
                      'Transfers bypass router limitations and use the full bandwidth of your device’s Wi-Fi chip.',
                ),
                const SizedBox(height: 16),
                _buildBenefitRow(
                  context,
                  icon: LucideIcons.shieldAlert,
                  title: 'Bypasses Router Blocks',
                  subtitle:
                      'Solves "No route to host" errors caused by router AP/Client Isolation (which stops local devices from talking).',
                ),
                const SizedBox(height: 16),
                _buildBenefitRow(
                  context,
                  icon: LucideIcons.wifiOff,
                  title: 'Works Completely Offline',
                  subtitle:
                      'No active internet connection or router needed. Share files in a park, plane, or car.',
                ),
                const SizedBox(height: 28),
                Text(
                  'How to configure:',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _buildStepRow(
                  context,
                  '1',
                  'Tap "Enable Hotspot" or "Hotspot Settings" to open your device\'s configuration.',
                ),
                _buildStepRow(
                  context,
                  '2',
                  'Turn on "Portable Hotspot" or "Internet Sharing".',
                ),
                _buildStepRow(
                  context,
                  '3',
                  'On the receiver device, connect to the new Wi-Fi hotspot network.',
                ),
                _buildStepRow(
                  context,
                  '4',
                  'Select files to send, scan the QR code, and enjoy maximum speed!',
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Widget _buildBenefitRow(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String subtitle,
}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: ZyncTheme.greenDim,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: ZyncTheme.green, size: 20),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    ],
  );
}

Widget _buildStepRow(BuildContext context, String step, String text) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: ZyncTheme.orangeDim,
            shape: BoxShape.circle,
          ),
          child: Text(
            step,
            style: const TextStyle(
              color: ZyncTheme.orange,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
        ),
      ],
    ),
  );
}
