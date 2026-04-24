# Zync

Zync is a cross-platform peer-to-peer (P2P) file-sharing application designed for fast, local transfers between Android, Windows, and Linux devices. Built with Flutter.

## Features

- Cross-Platform Support: Seamlessly share files between Android, Windows, and Linux.
- Local Network Discovery: Automatically discovers devices on the local network using multicast DNS (mDNS) without requiring manual IP entry.
- QR Code Pairing: Quickly connect devices by scanning a dynamically generated QR code containing the server connection details (Camera scanning available on Android).
- Modern Aesthetic: Features an AMOLED dark mode, large typography, and a "view at the top, interact at the bottom" layout philosophy.
- Direct File Transfers: Hosts a local HTTP server on the sender device for direct, high-speed file transfers.
- Activity History: Maintains a persistent local record of shared files.

## Technical Stack

- Framework: Flutter
- State Management: Riverpod
- Navigation: GoRouter
- Networking: shelf (HTTP server), multicast_dns (discovery)
- Local Storage: sqflite, sqflite_common_ffi (desktop support)
- Utilities: qr_flutter, mobile_scanner, file_picker, device_info_plus

## Installation

### Prerequisites

For Linux builds, `libsecret-devel` is a required dependency. Install it using your distribution's package manager before building the project.

### Building and Running

1. Ensure you have the Flutter SDK installed and configured.
2. Clone the repository.
3. Fetch the dependencies:
   ```bash
   flutter pub get
   ```
4. Run the project:
   ```bash
   flutter run
   ```
