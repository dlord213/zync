import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:device_info_plus/device_info_plus.dart';

class DeviceMetadata {
  final String deviceName;
  final String osType;

  DeviceMetadata({required this.deviceName, required this.osType});
}

class DeviceInfoNotifier extends AsyncNotifier<DeviceMetadata> {
  @override
  Future<DeviceMetadata> build() async {
    final deviceInfo = DeviceInfoPlugin();
    String deviceName = "Unknown Device";
    String osType = Platform.operatingSystem;

    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceName = '${androidInfo.brand} ${androidInfo.model}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceName = iosInfo.name;
      } else if (Platform.isLinux) {
        final linuxInfo = await deviceInfo.linuxInfo;
        deviceName = linuxInfo.prettyName;
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        deviceName = windowsInfo.productName;
      } else if (Platform.isMacOS) {
        final macInfo = await deviceInfo.macOsInfo;
        deviceName = macInfo.computerName;
      }
    } catch (e) {
      deviceName = "Unknown $osType Device";
    }

    return DeviceMetadata(deviceName: deviceName, osType: osType);
  }
}

final deviceInfoProvider = AsyncNotifierProvider<DeviceInfoNotifier, DeviceMetadata>(() {
  return DeviceInfoNotifier();
});
